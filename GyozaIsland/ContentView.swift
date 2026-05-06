import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var panelState: IslandPanelState
    @StateObject private var musicController = MusicController()
    @State private var isHoveringIsland = false
    @State private var expansionProgress: CGFloat = 0
    @State private var currentPage: Int = 0
    // Actual HStack offset in points. Animating this CGFloat directly gives a
    // smooth slide — changing Int currentPage inside withAnimation causes an
    // instant 430pt jump followed by a partial spring, which feels like a stutter.
    @State private var pageOffset: CGFloat = 0

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
        panelState.isInteractionActive || panelState.isFileDragActive
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
            if !newValue {
                withAnimation(hoverOutAnimation) {
                    currentPage = 0
                    pageOffset = 0
                }
            }
        }
        // Live visual feedback while the user is swiping.
        .onChange(of: panelState.pageSwipeAccum) { _, accum in
            guard contentProgress > 0.95 else { return }
            let base = -(CGFloat(currentPage) * expandedWidth)
            let candidate = base + accum
            // Rubber band when dragging past the first or last page.
            if candidate > 0 {
                pageOffset = candidate * 0.25
            } else if candidate < -expandedWidth {
                pageOffset = -expandedWidth + (candidate + expandedWidth) * 0.25
            } else {
                pageOffset = candidate
            }
        }
        // Finger lifted — commit or snap back with a full spring from current pos.
        .onChange(of: panelState.pageSwipeCommit) { _, _ in
            let base = -(CGFloat(currentPage) * expandedWidth)
            let displacement = pageOffset - base
            let newPage: Int
            if displacement < -25 && currentPage < 1 {
                newPage = 1
            } else if displacement > 25 && currentPage > 0 {
                newPage = 0
            } else {
                newPage = currentPage
            }
            currentPage = newPage
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                pageOffset = -(CGFloat(newPage) * expandedWidth)
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
        // contentShape and onHover must sit on the correctly-sized frame so
        // the hover zone matches the actual pill/card, not the full panel area.
        .contentShape(IslandShellShape(progress: bodyProgress))
        .onHover { isHovering in
            if isHovering != isHoveringIsland { isHoveringIsland = isHovering }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var islandBody: some View {
        ZStack(alignment: .top) {
            islandSurface
            if contentProgress > 0.01 {
                pagedContent
            }
        }
    }

    private var pagedContent: some View {
        // Top alignment matches the original mediaContent placement — content
        // starts at padding(.top, 38) from the island top, same as before.
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                page0Content
                    .frame(width: expandedWidth)
                page1Content
                    .frame(width: expandedWidth)
            }
            .frame(width: expandedWidth, alignment: .leading)
            .offset(x: pageOffset)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                pageIndicator
                    .padding(.bottom, 10)
                    .opacity(contentProgress)
            }
            .frame(height: expandedHeight)
            .allowsHitTesting(false)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .local)
                .onChanged { value in
                    guard contentProgress > 0.95 else { return }
                    let base = -(CGFloat(currentPage) * expandedWidth)
                    let candidate = base + value.translation.width
                    if candidate > 0 {
                        pageOffset = candidate * 0.25
                    } else if candidate < -expandedWidth {
                        pageOffset = -expandedWidth + (candidate + expandedWidth) * 0.25
                    } else {
                        pageOffset = candidate
                    }
                }
                .onEnded { value in
                    guard contentProgress > 0.95 else { return }
                    let base = -(CGFloat(currentPage) * expandedWidth)
                    let displacement = pageOffset - base
                    let predicted = value.predictedEndTranslation.width
                    let newPage: Int
                    if (displacement < -25 || predicted < -50) && currentPage < 1 {
                        newPage = 1
                    } else if (displacement > 25 || predicted > 50) && currentPage > 0 {
                        newPage = 0
                    } else {
                        newPage = currentPage
                    }
                    currentPage = newPage
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        pageOffset = -(CGFloat(newPage) * expandedWidth)
                    }
                }
        )
        .opacity(contentProgress)
        .scaleEffect(lerp(0.98, 1, contentProgress), anchor: .center)
        .allowsHitTesting(contentProgress > 0.95)
    }

    private var page1Content: some View {
        Color.clear
    }

    private var pageIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(currentPage == index ? Color.white.opacity(0.8) : Color.white.opacity(0.25))
                    .frame(width: 4, height: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
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

    private var page0Content: some View {
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
                    panelState.isAirDropTargeted
                        ? Color.white.opacity(0.30)
                        : panelState.isFileDragActive
                            ? Color.white.opacity(0.22)
                            : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            Color.white.opacity(panelState.isAirDropTargeted ? 0.65 : panelState.isFileDragActive ? 0.42 : 0.0),
                            lineWidth: panelState.isAirDropTargeted ? 1.5 : 1
                        )
                }
                .scaleEffect(panelState.isAirDropTargeted ? 1.06 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: panelState.isAirDropTargeted)
        }
        .buttonStyle(.plain)
    }

    private var airDropIcon: some View {
        Group {
            if let image = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AirDrop.icns") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
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
