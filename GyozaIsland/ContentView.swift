import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var panelState: IslandPanelState
    @StateObject private var musicController = MusicController()
    @State private var isHoveringIsland = false
    @State private var isAirDropTargeted = false
    @State private var isFileDragInside = false
    @State private var expansionProgress: CGFloat = 0

    // The collapsed dimensions come from the detected notch silhouette so the
    // resting pill perfectly overlaps the real notch (or the menu bar on
    // non-notch Macs). Falls back to the published default until a real value
    // is reported.
    private var collapsedWidth: CGFloat { panelState.collapsedSize.width }
    private var collapsedHeight: CGFloat { panelState.collapsedSize.height }
    private let expandedWidth: CGFloat = 430
    private let expandedHeight: CGFloat = 150
    // Spring physics give the Apple-like bounce-then-settle feel. Lower
    // damping on hover-in for a small overshoot; higher damping on hover-out
    // so the pill returns to the notch without jiggle.
    private let hoverInAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    private let hoverOutAnimation = Animation.spring(response: 0.50, dampingFraction: 0.92)

    private var isExpandedTarget: Bool {
        panelState.isInteractionActive || panelState.isFileDragActive || isHoveringIsland || isFileDragInside
    }

    private var shapeProgress: CGFloat {
        expansionProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(width: 430, height: 164, alignment: .top)
                .padding(.top, 0)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .onAppear {
            expansionProgress = isExpandedTarget ? 1 : 0
            musicController.refreshNowPlaying()
        }
        .onChange(of: isExpandedTarget) { _, newValue in
            withAnimation(newValue ? hoverInAnimation : hoverOutAnimation) {
                expansionProgress = newValue ? 1 : 0
            }
            if newValue {
                musicController.refreshNowPlaying()
            }
        }
    }

    private var island: some View {
        let islandWidth = lerp(collapsedWidth, expandedWidth, bodyProgress)
        let islandHeight = lerp(collapsedHeight, expandedHeight, bodyProgress)

        return ZStack(alignment: .top) {
            islandShadow
                .frame(width: islandWidth, height: islandHeight, alignment: .top)

            islandBody
                .frame(width: islandWidth, height: islandHeight, alignment: .top)
                .clipShape(IslandShellShape(progress: bodyProgress))
                .compositingGroup()
        }
        .foregroundColor(.white)
        .frame(width: islandWidth, height: islandHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(IslandShellShape(progress: bodyProgress))
        .onHover { isHovering in
            if isHovering != isHoveringIsland {
                isHoveringIsland = isHovering
            }
        }
    }

    private var islandBody: some View {
        ZStack(alignment: .top) {
            islandSurface
            dragExpansionTarget
            if contentProgress > 0.01 {
                mediaContent
            }
        }
    }

    private var islandShadow: some View {
        IslandShellShape(progress: bodyProgress)
            .fill(Color.black.opacity(0.001))
            .shadow(
                color: .black.opacity(shadowProgress * 0.1),
                radius: lerp(3, 13, shadowProgress),
                x: 0,
                y: lerp(1, 13, shadowProgress)
            )
            .allowsHitTesting(false)
    }

    private var islandSurface: some View {
        IslandShellShape(progress: bodyProgress)
            .fill(Color.black)
            .overlay(
                IslandShellShape(progress: bodyProgress)
                    .stroke(Color.white.opacity(lerp(0.015, 0.08, bodyProgress)), lineWidth: 1)
            )
    }

    private var dragExpansionTarget: some View {
        Color.clear
            .contentShape(IslandShellShape(progress: bodyProgress))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFileDragInside) { providers in
                handleAirDrop(providers: providers)
            }
    }

    private var mediaContent: some View {
        HStack(alignment: .center, spacing: 18) {
            Button {
                musicController.openMusicApp()
            } label: {
                albumArtwork
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(musicController.trackTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(musicController.trackSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 16) {
                    mediaButton(systemName: "backward.fill", symbolSize: 13, buttonSize: 38) {
                        musicController.previousTrack()
                    }

                    mediaButton(
                        systemName: musicController.prefersPauseIcon ? "pause.fill" : "play.fill",
                        symbolSize: 18,
                        buttonSize: 44
                    ) {
                        musicController.togglePlayPause()
                    }

                    mediaButton(systemName: "forward.fill", symbolSize: 13, buttonSize: 38) {
                        musicController.nextTrack()
                    }

                    Spacer(minLength: 0)
                }
            }

            airDropButton
        }
        .padding(.top, 38)
        .padding(.horizontal, 30)
        .opacity(contentProgress)
        .scaleEffect(lerp(0.98, 1, contentProgress), anchor: .center)
        .allowsHitTesting(contentProgress > 0.95)
    }

    private func mediaButton(systemName: String, symbolSize: CGFloat, buttonSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(.white.opacity(0.13), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var airDropButton: some View {
        Button {
            openAirDrop()
        } label: {
            airDropIcon
            .frame(width: 58, height: 58)
            .background(
                (isAirDropTargeted ? Color.white.opacity(0.22) : Color.white.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isAirDropTargeted ? 0.42 : 0.0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isAirDropTargeted) { providers in
            handleAirDrop(providers: providers)
        }
    }

    private var airDropIcon: some View {
        Group {
            if let image = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AirDrop.icns") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else {
                Image(systemName: "airdrop")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var albumArtwork: some View {
        ZStack {
            if let image = musicController.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func openAirDrop() {
        let airDropURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: airDropURL, configuration: configuration)
    }

    private func handleAirDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data,
                          let value = String(data: data, encoding: .utf8),
                          let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    urls.append(url)
                } else if let value = item as? String,
                          let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            sendViaAirDrop(urls)
        }

        return true
    }

    private func sendViaAirDrop(_ urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else {
            openAirDrop()
            return
        }

        service.perform(withItems: urls)
    }
}

private struct IslandShellShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1)
        // Keep the collapsed notch softly rounded, then flatten the top
        // corners as the island expands so the top edge visually attaches to
        // the screen/menu bar without exposing the background at the corners.
        // Bottom corners stay large for the expanded card feel.
        let topRadius = lerp(6, 0, p)
        let bottomRadius = lerp(8, 44, p)

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
                radius: topRadius
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
                radius: bottomRadius
            )
            path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
                radius: bottomRadius
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.minY),
                radius: topRadius
            )
            path.closeSubpath()
        }
    }
}

private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
    start + (end - start) * progress
}

private func delayedProgress(_ progress: CGFloat, start: CGFloat) -> CGFloat {
    let normalized = (progress - start) / (1 - start)
    return min(max(normalized, 0), 1)
}

private extension ContentView {
    // The spring driving expansionProgress already supplies the easing curve,
    // so this passes through directly.
    var bodyProgress: CGFloat {
        shapeProgress
    }

    // Delay the shadow until the pill is meaningfully extended; at rest the
    // pill has no shadow so it blends with the real notch.
    var shadowProgress: CGFloat {
        delayedProgress(bodyProgress, start: 0.45)
    }

    var contentProgress: CGFloat {
        delayedProgress(bodyProgress, start: 0.72)
    }
}
