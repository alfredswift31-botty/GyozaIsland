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

private let filenamesPasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

final class IslandPanelState: ObservableObject {
    @Published var isInteractionActive = false
    @Published var isFileDragActive = false
    @Published var isAirDropTargeted = false
    @Published var collapsedSize: CGSize = CGSize(width: 200, height: 32)
    @Published var bandHeight: CGFloat = 37
    @Published var pageSwipeDirection: Int = 0
    @Published var pageSwipeTrigger: Int = 0
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
    private var scrollLocalMonitor: Any?
    private var scrollGlobalMonitor: Any?
    private var swipeAccum: CGFloat = 0
    private var swipeCommitLocked = false
    private let swipeScrollMultiplier: CGFloat = 2.6
    private let swipeTriggerThreshold: CGFloat = 22
    private let panelState = IslandPanelState()
    private let panelSize = NSSize(width: 450, height: 186)
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
        // Must be above the menu bar (kCGStatusWindowLevel = 25) to draw over it,
        // but BELOW the system drag cursor window (kCGDraggingWindowLevel = 500).
        // AppKit only delivers drops to windows beneath the dragging window — at
        // CGShieldingWindowLevel the panel is above the drag cursor so draggingEntered
        // is never called and all drops fall through silently.
        panel.level = NSWindow.Level(rawValue: 400)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.alphaValue = 1
        let dropContainer = DragAwareContainerView(panelState: panelState)
        dropContainer.frame = NSRect(origin: .zero, size: panelSize)
        dropContainer.autoresizingMask = [.width, .height]
        dropContainer.wantsLayer = true
        dropContainer.layer?.backgroundColor = NSColor.clear.cgColor
        dropContainer.layer?.masksToBounds = false

        let hostingView = NSHostingView(rootView: ContentView(panelState: panelState))
        hostingView.frame = dropContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        dropContainer.addSubview(hostingView)
        // Prevent SwiftUI's internal drag machinery from intercepting drags
        // before DragAwareContainerView gets them.
        hostingView.unregisterDraggedTypes()
        panel.contentView = dropContainer

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
        if let monitor = scrollLocalMonitor {
            NSEvent.removeMonitor(monitor)
            scrollLocalMonitor = nil
        }
        if let monitor = scrollGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            scrollGlobalMonitor = nil
        }
    }

    /// Drive hover and drag detection from real pointer events instead of
    /// polling. File drags do not reliably emit plain mouse-moved events, so
    /// dragged events must feed the same activation-zone logic.
    private func startMouseTracking() {
        let pointerEvents: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseUp,
            .rightMouseUp,
            .otherMouseUp
        ]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] _ in
            self?.updatePanelVisibility()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents) { [weak self] event in
            self?.updatePanelVisibility()
            return event
        }
        // Trackpad swipe = scroll wheel events. The panel is non-activating so
        // our app is never the key app — local monitor alone won't fire when
        // another app is active. Use both, same pattern as mouse monitors.
        scrollLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event)
            return event
        }
        scrollGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event)
        }
        updatePanelVisibility()
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard let panel = islandPanel,
              panelState.isInteractionActive,
              panel.frame.contains(NSEvent.mouseLocation) else {
            if event.phase == .ended || event.phase == .cancelled {
                swipeAccum = 0
                swipeCommitLocked = false
            }
            return
        }
        // Page turns should come from intentional horizontal swipes, not
        // diagonal/vertical scrolling over the island.
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }

        switch event.phase {
        case .began:
            swipeAccum = 0
            swipeCommitLocked = false
        case .changed:
            guard !swipeCommitLocked else { return }
            swipeAccum += event.scrollingDeltaX * swipeScrollMultiplier
            if abs(swipeAccum) > swipeTriggerThreshold {
                let direction = swipeAccum < 0 ? -1 : 1
                print(
                    "[GyozaIsland] scroll swipe trigger",
                    "accum=\(swipeAccum)",
                    "threshold=\(swipeTriggerThreshold)",
                    "direction=\(direction < 0 ? "left" : "right")"
                )
                panelState.pageSwipeDirection = direction
                panelState.pageSwipeTrigger += 1
                swipeAccum = 0
                swipeCommitLocked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.swipeCommitLocked = false
                }
            }
        case .ended, .cancelled:
            swipeAccum = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.swipeCommitLocked = false
            }
        default:
            break
        }
    }

    private func updatePanelVisibility() {
        guard let panel = islandPanel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = screen(containing: mouseLocation) ?? panel.screen ?? NSScreen.main
        guard let screen = activeScreen else { return }

        let panelSize = panel.frame.size
        positionPanel(panel, on: screen, size: panelSize)

        let activationZone = activationRect(for: screen, panelSize: panelSize)
        let alreadyExpanded = panelState.isInteractionActive

        // Two-stage: tight notch zone opens the card; full panel frame only
        // keeps it open once already expanded. This prevents the card from
        // opening when the cursor drifts near the menu bar from below.
        let shouldExpand = activationZone.contains(mouseLocation)
                        || (alreadyExpanded && panel.frame.contains(mouseLocation))

        if shouldExpand && !alreadyExpanded {
            print(
                "[GyozaIsland] hover activation",
                "rect=(x:\(activationZone.origin.x), y:\(activationZone.origin.y), w:\(activationZone.width), h:\(activationZone.height))",
                "mouse=(x:\(mouseLocation.x), y:\(mouseLocation.y))"
            )
        }

        if !shouldExpand {
            swipeAccum = 0
            swipeCommitLocked = false
        }
        panelState.isInteractionActive = shouldExpand
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen, size: NSSize) {
        let metrics = notchMetrics(for: screen, panelSize: size)
        let origin = NSPoint(
            x: metrics.midpointX - size.width / 2,
            y: metrics.panelOriginY
        )
        // Only reposition when the origin actually changes — calling setFrameOrigin
        // unconditionally on every drag event resets AppKit's drag destination
        // tracking, causing drops to fall through to the window below.
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }

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
        // Slightly inset the detected notch dimensions so the island opens
        // only when the cursor is inside the physical cutout, not merely near
        // the menu-bar reserve around it.
        let width = max(metrics.notchWidth - 10, 1)
        let height = max(metrics.bandHeight - 4, 1)
        return NSRect(
            x: metrics.midpointX - width / 2,
            y: metrics.bandMinY + 2,
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

final class DragAwareContainerView: NSView {
    private weak var panelState: IslandPanelState?

    // Modern Finder drags lead with promised-file-url; register for it so
    // draggingEntered is called even before the file data is materialised.
    private static let promisedFileURLType =
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")

    init(panelState: IslandPanelState) {
        self.panelState = panelState
        super.init(frame: .zero)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            filenamesPasteboardType,
            DragAwareContainerView.promisedFileURLType
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Only inspect pasteboard TYPES here — never read content during tracking.
    // Promised file URLs are not resolvable until performDragOperation; calling
    // readObjects() during draggingEntered/Updated returns empty and causes the
    // operation to fall back to [] which cancels the drag destination.
    private func canAcceptDrag(_ sender: NSDraggingInfo) -> Bool {
        guard let types = sender.draggingPasteboard.types else { return false }
        return types.contains(.fileURL) ||
               types.contains(.URL) ||
               types.contains(filenamesPasteboardType) ||
               types.contains(DragAwareContainerView.promisedFileURLType)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender) else {
            print("[GyozaIsland] draggingEntered – rejected, types: \(sender.draggingPasteboard.types ?? [])")
            return []
        }
        print("[GyozaIsland] draggingEntered – accepted, types: \(sender.draggingPasteboard.types ?? [])")
        panelState?.isFileDragActive = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender) else { return [] }
        panelState?.isFileDragActive = true
        panelState?.isAirDropTargeted = isOverAirDropButton(sender.draggingLocation)
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let ok = canAcceptDrag(sender)
        print("[GyozaIsland] prepareForDragOperation → \(ok)")
        return ok
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        print("[GyozaIsland] performDragOperation – types: \(sender.draggingPasteboard.types ?? [])")
        panelState?.isFileDragActive = false
        panelState?.isAirDropTargeted = false

        let items = resolvedItems(from: sender.draggingPasteboard)
        print("[GyozaIsland] resolved \(items.count) item(s)")
        guard !items.isEmpty else { return false }

        let airDropName = NSSharingService.Name(rawValue: "com.apple.share.AirDrop.send")
        if let service = NSSharingService(named: airDropName) {
            print("[GyozaIsland] launching AirDrop service")
            service.perform(withItems: items)
        } else {
            print("[GyozaIsland] AirDrop unavailable – showing sharing picker")
            showSharingPicker(items: items, draggingInfo: sender)
        }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        print("[GyozaIsland] concludeDragOperation")
        panelState?.isFileDragActive = false
        panelState?.isAirDropTargeted = false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        print("[GyozaIsland] draggingExited")
        panelState?.isFileDragActive = false
        panelState?.isAirDropTargeted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        panelState?.isFileDragActive = false
        panelState?.isAirDropTargeted = false
    }

    // AirDrop button occupies the right end of the media row.
    // Panel: 450×172 (NSView coords, Y from bottom). Button: ~58×58.
    private func isOverAirDropButton(_ windowPoint: NSPoint) -> Bool {
        let p = convert(windowPoint, from: nil)
        return p.x > 330 && p.y > 40 && p.y < 140
    }

    // Read actual file items only at drop time (performDragOperation).
    // Try promised receivers first (modern Finder), then direct URLs, then legacy paths.
    private func resolvedItems(from pasteboard: NSPasteboard) -> [Any] {
        if let receivers = pasteboard.readObjects(
                forClasses: [NSFilePromiseReceiver.self], options: nil
            ) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            print("[GyozaIsland] using \(receivers.count) NSFilePromiseReceiver(s)")
            return receivers
        }
        if let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], !urls.isEmpty {
            print("[GyozaIsland] using \(urls.count) file URL(s): \(urls.map(\.lastPathComponent))")
            return urls
        }
        if let paths = pasteboard.propertyList(forType: filenamesPasteboardType) as? [String] {
            let urls = paths.map(URL.init(fileURLWithPath:))
            print("[GyozaIsland] using \(urls.count) legacy path URL(s)")
            return urls
        }
        return []
    }

    private func showSharingPicker(items: [Any], draggingInfo: NSDraggingInfo) {
        let viewLocation = convert(draggingInfo.draggingLocation, from: nil)
        let picker = NSSharingServicePicker(items: items)
        picker.show(
            relativeTo: NSRect(x: viewLocation.x, y: viewLocation.y, width: 1, height: 1),
            of: self,
            preferredEdge: .minY
        )
    }
}
