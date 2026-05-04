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
    private var mouseTrackingTimer: Timer?
    private var isPanelVisible = false
    private let panelState = IslandPanelState()
    private let panelSize = NSSize(width: 284, height: 96)
    private let collapsedNotchHeight: CGFloat = 30
    private let visualOffsetY: CGFloat = 10

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
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.alphaValue = 0
        let hostingView = NSHostingView(rootView: ContentView(panelState: panelState))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            positionPanel(panel, on: screen, size: panelSize)
        }

        islandPanel = panel
        startMouseTracking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
    }

    private func startMouseTracking() {
        mouseTrackingTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            self?.updatePanelVisibility()
        }
        RunLoop.main.add(mouseTrackingTimer!, forMode: .common)
    }

    private func updatePanelVisibility() {
        guard let panel = islandPanel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = screen(containing: mouseLocation) ?? panel.screen ?? NSScreen.main
        guard let screen = activeScreen else { return }

        let panelSize = panel.frame.size
        positionPanel(panel, on: screen, size: panelSize)

        let activationZone = activationRect(for: screen, panelSize: panelSize)
        let shouldShowPanel = activationZone.contains(mouseLocation) || panel.frame.contains(mouseLocation)
        panelState.isInteractionActive = shouldShowPanel

        guard shouldShowPanel != isPanelVisible else { return }
        isPanelVisible = shouldShowPanel

        if shouldShowPanel {
            showPanel(panel)
        } else {
            hidePanel(panel)
        }
    }

    private func showPanel(_ panel: NSPanel) {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            guard let self, let panel, !self.isPanelVisible else { return }
            panel.orderOut(nil)
        })
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen, size: NSSize) {
        let metrics = notchMetrics(for: screen, panelSize: size)
        let origin = NSPoint(
            x: metrics.midpointX - size.width / 2,
            y: metrics.panelOriginY
        )
        panel.setFrameOrigin(origin)
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

        // Keep the collapsed fake notch vertically centered in the top reserved band,
        // while letting the expanded state grow downward from the same top anchor.
        let panelTopY = bandMinY + (bandHeight + collapsedNotchHeight) / 2
        let panelOriginY = panelTopY - panelSize.height + visualOffsetY

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
