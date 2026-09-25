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

/// Diagnostics for Debug builds only. Release builds never build the message,
/// so drag types, file names and playback details stay out of stdout.
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

struct TemporaryShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

final class IslandPanelState: ObservableObject {
    @Published var isInteractionActive = false
    @Published var isFileDragActive = false
    @Published var isAirDropTargeted = false
    @Published var isShelfDropTargeted = false
    @Published var temporaryShelfItems: [TemporaryShelfItem] = []
    @Published var collapsedSize: CGSize = CGSize(width: 200, height: 32)
    @Published var bandHeight: CGFloat = 37
    @Published var currentPage: Int = 0
    @Published var pageSwipeDirection: Int = 0
    @Published var pageSwipeTrigger: Int = 0

    func addTemporaryShelfFiles(_ urls: [URL]) {
        var seenURLs = Set(temporaryShelfItems.map(\.url))
        let uniqueItems = urls.compactMap { url -> TemporaryShelfItem? in
            let fileURL = url.standardizedFileURL
            guard fileURL.isFileURL, !seenURLs.contains(fileURL) else { return nil }
            seenURLs.insert(fileURL)
            return TemporaryShelfItem(url: fileURL)
        }

        guard !uniqueItems.isEmpty else { return }
        temporaryShelfItems.append(contentsOf: uniqueItems)
    }

    func removeTemporaryShelfItem(_ item: TemporaryShelfItem) {
        temporaryShelfItems.removeAll { $0.id == item.id }
    }
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
    // Bumped whenever the lock is re-armed or reset, so an unlock scheduled by
    // an earlier swipe can't release the lock of a newer one early.
    private var swipeLockGeneration = 0
    private let swipeScrollMultiplier: CGFloat = 2.6
    private let swipeTriggerThreshold: CGFloat = 22
    private let panelState = IslandPanelState()
    private let panelSize = NSSize(width: 450, height: 186)
    private let collapsedNotchHeight: CGFloat = 32

    func applicationDidFinishLaunching(_ notification: Notification) {
        DragAwareContainerView.removeStalePromisedFiles()

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
                resetSwipeTracking()
            }
            return
        }
        // Page turns should come from intentional horizontal swipes, not
        // diagonal/vertical scrolling over the island.
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }

        switch event.phase {
        case .began:
            resetSwipeTracking()
        case .changed:
            guard !swipeCommitLocked else { return }
            swipeAccum += event.scrollingDeltaX * swipeScrollMultiplier
            if abs(swipeAccum) > swipeTriggerThreshold {
                let direction = swipeAccum < 0 ? -1 : 1
                debugLog(
                    "[GyozaIsland] scroll swipe trigger accum=\(swipeAccum) threshold=\(swipeTriggerThreshold) direction=\(direction < 0 ? "left" : "right")"
                )
                panelState.pageSwipeDirection = direction
                panelState.pageSwipeTrigger += 1
                swipeAccum = 0
                swipeCommitLocked = true
                scheduleSwipeUnlock(after: 0.4)
            }
        case .ended, .cancelled:
            swipeAccum = 0
            scheduleSwipeUnlock(after: 0.15)
        default:
            break
        }
    }

    private func scheduleSwipeUnlock(after delay: TimeInterval) {
        swipeLockGeneration += 1
        let generation = swipeLockGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.swipeLockGeneration == generation else { return }
            self.swipeCommitLocked = false
        }
    }

    private func resetSwipeTracking() {
        swipeLockGeneration += 1
        swipeAccum = 0
        swipeCommitLocked = false
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
        // Page 1 is a working shelf mode: keep it open while the user goes to
        // fetch files or drag shelf items back out, then let page 0 collapse
        // normally after they swipe back.
        let shelfModeKeepsOpen = panelState.currentPage == 1
        let shouldExpand = activationZone.contains(mouseLocation)
                        || shelfModeKeepsOpen
                        || (alreadyExpanded && panel.frame.contains(mouseLocation))

        if shouldExpand && !alreadyExpanded {
            debugLog(
                "[GyozaIsland] hover activation rect=(x:\(activationZone.origin.x), y:\(activationZone.origin.y), w:\(activationZone.width), h:\(activationZone.height)) mouse=(x:\(mouseLocation.x), y:\(mouseLocation.y))"
            )
        }

        if !shouldExpand {
            resetSwipeTracking()
        }
        // This runs for every pointer event system-wide, and @Published notifies
        // on every write even when the value is unchanged. Writing blindly made
        // ContentView re-render on each mouse move anywhere on screen.
        if alreadyExpanded != shouldExpand {
            panelState.isInteractionActive = shouldExpand
        }
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

    // Everything that ends up as a file on disk: direct file URLs, legacy
    // filename lists, and file promises (Photos, Mail attachments, etc.).
    private static let fileDragTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, filenamesPasteboardType, promisedFileURLType]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    // Promised files are written here. They are session-only, like the shelf.
    private static let promisedFilesDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GyozaIslandDrops", isDirectory: true)

    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(panelState: IslandPanelState) {
        self.panelState = panelState
        super.init(frame: .zero)
        registerForDraggedTypes(Self.fileDragTypes + [.URL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func removeStalePromisedFiles() {
        try? FileManager.default.removeItem(at: promisedFilesDirectory)
    }

    private var isShelfPage: Bool {
        panelState?.currentPage == 1
    }

    // Only inspect pasteboard TYPES here — never read content during tracking.
    // Promised file URLs are not resolvable until performDragOperation; calling
    // readObjects() during draggingEntered/Updated returns empty and causes the
    // operation to fall back to [] which cancels the drag destination.
    private func canAcceptDrag(_ sender: NSDraggingInfo) -> Bool {
        guard let types = sender.draggingPasteboard.types else { return false }
        if types.contains(where: { Self.fileDragTypes.contains($0) }) {
            return true
        }
        // Web links can be AirDropped but have no place on the file shelf.
        return !isShelfPage && types.contains(.URL)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender) else {
            debugLog("[GyozaIsland] draggingEntered – rejected, types: \(sender.draggingPasteboard.types ?? [])")
            return []
        }
        debugLog("[GyozaIsland] draggingEntered – accepted, types: \(sender.draggingPasteboard.types ?? [])")
        updateDragState(for: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender) else { return [] }
        updateDragState(for: sender)
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let ok = canAcceptDrag(sender)
        debugLog("[GyozaIsland] prepareForDragOperation → \(ok)")
        return ok
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        debugLog("[GyozaIsland] performDragOperation – types: \(pasteboard.types ?? [])")
        let toShelf = isShelfPage
        let anchor = convert(sender.draggingLocation, from: nil)
        clearDragState()

        // Files that already exist on disk (Finder and most apps). Checked
        // before promises so a drag that offers both uses the real file.
        let urls = fileURLs(from: pasteboard)
        if !urls.isEmpty {
            debugLog("[GyozaIsland] drop resolved \(urls.count) file URL(s)")
            deliver(urls, toShelf: toShelf, anchor: anchor)
            return true
        }

        // Promise-only sources write their files asynchronously into a folder
        // we choose. Neither the shelf nor AirDrop can use them before then.
        if let receivers = pasteboard.readObjects(
                forClasses: [NSFilePromiseReceiver.self], options: nil
            ) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            debugLog("[GyozaIsland] receiving \(receivers.count) file promise(s)")
            receivePromisedFiles(from: receivers) { [weak self] receivedURLs in
                self?.deliver(receivedURLs, toShelf: toShelf, anchor: anchor)
            }
            return true
        }

        // Web links can be AirDropped but have no place on the file shelf.
        if !toShelf,
           let links = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !links.isEmpty {
            debugLog("[GyozaIsland] sharing \(links.count) link(s)")
            share(links, anchor: anchor)
            return true
        }

        return false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        debugLog("[GyozaIsland] concludeDragOperation")
        clearDragState()
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        debugLog("[GyozaIsland] draggingExited")
        clearDragState()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearDragState()
    }

    private func updateDragState(for sender: NSDraggingInfo) {
        let onShelf = isShelfPage
        setDragState(
            active: true,
            shelfTargeted: onShelf,
            airDropTargeted: !onShelf && isOverAirDropButton(sender.draggingLocation)
        )
    }

    private func clearDragState() {
        setDragState(active: false, shelfTargeted: false, airDropTargeted: false)
    }

    // draggingUpdated fires on every pointer move, and @Published notifies on
    // every write, so only write values that actually change.
    private func setDragState(active: Bool, shelfTargeted: Bool, airDropTargeted: Bool) {
        guard let panelState else { return }
        if panelState.isFileDragActive != active {
            panelState.isFileDragActive = active
        }
        if panelState.isShelfDropTargeted != shelfTargeted {
            panelState.isShelfDropTargeted = shelfTargeted
        }
        if panelState.isAirDropTargeted != airDropTargeted {
            panelState.isAirDropTargeted = airDropTargeted
        }
    }

    // AirDrop button occupies the right end of the media row.
    // Panel: 450×186 (NSView coords, Y from bottom). Button: 58×58.
    private func isOverAirDropButton(_ windowPoint: NSPoint) -> Bool {
        let p = convert(windowPoint, from: nil)
        return p.x > 330 && p.y > 40 && p.y < 140
    }

    // Read actual file items only at drop time (performDragOperation):
    // direct file URLs first, then legacy paths.
    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], !urls.isEmpty {
            return urls.filter(\.isFileURL).map(\.standardizedFileURL)
        }
        if let paths = pasteboard.propertyList(forType: filenamesPasteboardType) as? [String] {
            return paths.map(URL.init(fileURLWithPath:)).map(\.standardizedFileURL)
        }
        return []
    }

    private func receivePromisedFiles(
        from receivers: [NSFilePromiseReceiver],
        completion: @escaping ([URL]) -> Void
    ) {
        let destination = Self.promisedFilesDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            debugLog("[GyozaIsland] couldn't create drop folder: \(error)")
            return
        }

        // Each receiver calls its reader once per promised file, on the
        // promise queue; hop to the main actor before touching shared state.
        let expectedFiles = receivers.reduce(0) { $0 + max($1.fileNames.count, 1) }
        let batch = PromisedFileBatch(expectedCount: expectedFiles, completion: completion)
        for receiver in receivers {
            receiver.receivePromisedFiles(
                atDestination: destination,
                options: [:],
                operationQueue: promiseQueue
            ) { @Sendable fileURL, error in
                Task { @MainActor in
                    if let error {
                        debugLog("[GyozaIsland] file promise failed: \(error)")
                        batch.receive(nil)
                    } else {
                        batch.receive(fileURL)
                    }
                }
            }
        }
    }

    private func deliver(_ urls: [URL], toShelf: Bool, anchor: NSPoint) {
        guard !urls.isEmpty else { return }
        if toShelf {
            panelState?.addTemporaryShelfFiles(urls)
        } else {
            share(urls, anchor: anchor)
        }
    }

    private func share(_ items: [Any], anchor: NSPoint) {
        if let service = NSSharingService(named: .sendViaAirDrop),
           service.canPerform(withItems: items) {
            debugLog("[GyozaIsland] launching AirDrop service")
            service.perform(withItems: items)
        } else {
            debugLog("[GyozaIsland] AirDrop unavailable – showing sharing picker")
            let picker = NSSharingServicePicker(items: items)
            picker.show(
                relativeTo: NSRect(x: anchor.x, y: anchor.y, width: 1, height: 1),
                of: self,
                preferredEdge: .minY
            )
        }
    }
}

/// Collects the files of one promise drop and reports them together, so a
/// multi-file drop opens a single AirDrop sheet.
private final class PromisedFileBatch {
    private var remaining: Int
    private var urls: [URL] = []
    private let completion: ([URL]) -> Void

    init(expectedCount: Int, completion: @escaping ([URL]) -> Void) {
        remaining = expectedCount
        self.completion = completion
    }

    func receive(_ url: URL?) {
        guard remaining > 0 else { return }
        if let url {
            urls.append(url)
        }
        remaining -= 1
        if remaining == 0 {
            completion(urls)
        }
    }
}
