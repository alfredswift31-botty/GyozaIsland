//
//  GyozaIslandApp.swift
//  GyozaIsland
//
//  Created by Aung Hpone Moe on 13/04/2026.
//

import SwiftUI
import AppKit
import QuartzCore
import Combine

final class IslandPanelState: ObservableObject {
    @Published var isInteractionActive = false
    /// Detected size of the real notch (or menu-bar-thickness fallback) so the
    /// resting pill can match the system silhouette exactly.
    @Published var collapsedSize: CGSize = CGSize(width: 200, height: 32)
    /// Full top-reserved band height (notch + any extra menu bar strip below
    /// it). The expanded shape's flare lands here so the wider card body
    /// starts exactly at the menu bar's bottom edge.
    @Published var bandHeight: CGFloat = 37
}

@main
struct GyozaIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct NotchMetrics {
        let midpointX: CGFloat
        let notchWidth: CGFloat
        let bandMinY: CGFloat
        let bandHeight: CGFloat
        let panelOriginY: CGFloat
    }

    private var islandPanel: NSPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let panelState = IslandPanelState()
    private let panelSize = NSSize(width: 450, height: 172)
    private let collapsedNotchHeight: CGFloat = 32

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Draw above the system menu bar so the pill's flare in the menu bar
        // reserve strip is actually visible — at .statusBar (25) the menu bar
        // background paints over the flare and the expanded card looks
        // disconnected from the top of the screen.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.alphaValue = 1
        let hostingView = NSHostingView(rootView: ContentView(panelState: panelState))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            positionPanel(panel, on: screen, size: panelSize)
        }

        islandPanel = panel
        // The pill is the notch — keep it on screen at all times so the
        // resting state visually replaces the real notch instead of popping in.
        panel.orderFrontRegardless()
        startMouseTracking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    /// Drive hover detection from real mouse-moved events instead of polling.
    /// Fires only when the cursor actually moves, so the app sleeps when idle
    /// and reacts within a single event tick when it doesn't.
    private func startMouseTracking() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updatePanelVisibility()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updatePanelVisibility()
            return event
        }
        // Run once on startup so the panel is positioned correctly before the
        // user moves the cursor.
        updatePanelVisibility()
    }

    private func updatePanelVisibility() {
        guard let panel = islandPanel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = screen(containing: mouseLocation) ?? panel.screen ?? NSScreen.main
        guard let screen = activeScreen else { return }

        let panelSize = panel.frame.size
        positionPanel(panel, on: screen, size: panelSize)

        let activationZone = activationRect(for: screen, panelSize: panelSize)
        let shouldExpand = activationZone.contains(mouseLocation) || panel.frame.contains(mouseLocation)
        panelState.isInteractionActive = shouldExpand
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen, size: NSSize) {
        let metrics = notchMetrics(for: screen, panelSize: size)
        let origin = NSPoint(
            x: metrics.midpointX - size.width / 2,
            y: metrics.panelOriginY
        )
        panel.setFrameOrigin(origin)

        // Surface the detected notch silhouette so the resting pill in
        // ContentView can match the system geometry exactly.
        let detected = CGSize(width: metrics.notchWidth, height: metrics.bandHeight)
        if panelState.collapsedSize != detected {
            panelState.collapsedSize = detected
        }
        if panelState.bandHeight != metrics.bandHeight {
            panelState.bandHeight = metrics.bandHeight
        }
    }

    private func activationRect(for screen: NSScreen, panelSize: NSSize) -> NSRect {
        let metrics = notchMetrics(for: screen, panelSize: panelSize)
        let width = max(panelSize.width + 72, metrics.notchWidth + 72, 260)
        let height = metrics.bandHeight + 18

        return NSRect(
            x: metrics.midpointX - width / 2,
            y: metrics.bandMinY - 12,
            width: width,
            height: height
        )
    }

    private func notchMetrics(for screen: NSScreen, panelSize: NSSize) -> NotchMetrics {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let safeAreaInsets = screen.safeAreaInsets

        let topReservedHeight = max(frame.maxY - visibleFrame.maxY, safeAreaInsets.top)
        let bandHeight = max(topReservedHeight, collapsedNotchHeight)
        let notchRegion = inferredNotchRegion(for: screen, bandHeight: bandHeight)
        let midpointX = notchRegion.midpointX
        let bandMinY = frame.maxY - bandHeight

        // Anchor the panel's top edge directly to the screen's top edge so the
        // collapsed pill sits inside the real notch reserve on notch Macs and
        // flush against the menu bar top on non-notch Macs. The shape grows
        // downward from this fixed top anchor on hover.
        let panelTopY = frame.maxY
        let panelOriginY = panelTopY - panelSize.height

        return NotchMetrics(
            midpointX: midpointX,
            notchWidth: notchRegion.width,
            bandMinY: bandMinY,
            bandHeight: bandHeight,
            panelOriginY: panelOriginY
        )
    }

    private func inferredNotchRegion(for screen: NSScreen, bandHeight: CGFloat) -> (midpointX: CGFloat, width: CGFloat) {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let safeAreaInsets = screen.safeAreaInsets

        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            if !leftArea.isEmpty, !rightArea.isEmpty, rightArea.minX > leftArea.maxX {
                let notchMinX = leftArea.maxX
                let notchMaxX = rightArea.minX
                let notchWidth = notchMaxX - notchMinX
                let midpointX = (notchMinX + notchMaxX) / 2
                return (midpointX, notchWidth)
            }
        }

        let safeMinX = frame.minX + safeAreaInsets.left
        let safeMaxX = frame.maxX - safeAreaInsets.right
        let midpointX = (safeMinX + safeMaxX) / 2
        let estimatedNotchWidth = max(frame.width - visibleFrame.width, safeAreaInsets.left + safeAreaInsets.right, 180)

        return (midpointX, estimatedNotchWidth)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
