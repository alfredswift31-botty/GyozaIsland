import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var panelState: IslandPanelState
    @State private var isHoveringIsland = false
    @State private var expansionProgress: CGFloat = 0
    @State private var isPlaying = false

    // The collapsed dimensions come from the detected notch silhouette so the
    // resting pill perfectly overlaps the real notch (or the menu bar on
    // non-notch Macs). Falls back to the published default until a real value
    // is reported.
    private var collapsedWidth: CGFloat { panelState.collapsedSize.width }
    private var collapsedHeight: CGFloat { panelState.collapsedSize.height }
    private let expandedWidth: CGFloat = 320
    private let expandedHeight: CGFloat = 110
    // Spring physics give the Apple-like bounce-then-settle feel. Lower
    // damping on hover-in for a small overshoot; higher damping on hover-out
    // so the pill returns to the notch without jiggle.
    private let hoverInAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    private let hoverOutAnimation = Animation.spring(response: 0.50, dampingFraction: 0.92)

    private var isExpandedTarget: Bool {
        panelState.isInteractionActive || isHoveringIsland
    }

    private var shapeProgress: CGFloat {
        expansionProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(width: 320, height: 124, alignment: .top)
                .padding(.top, 0)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .onAppear {
            expansionProgress = isExpandedTarget ? 1 : 0
        }
        .onChange(of: isExpandedTarget) { _, newValue in
            withAnimation(newValue ? hoverInAnimation : hoverOutAnimation) {
                expansionProgress = newValue ? 1 : 0
            }
        }
    }

    private var island: some View {
        ZStack(alignment: .top) {
            islandShadow
            islandSurface
            if bodyProgress > 0.01 {
                mediaContent
            }
        }
        .foregroundColor(.white)
        .frame(
            width: lerp(collapsedWidth, expandedWidth, bodyProgress),
            height: lerp(collapsedHeight, expandedHeight, bodyProgress),
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(IslandShellShape(progress: bodyProgress))
        .onHover { isHovering in
            if isHovering != isHoveringIsland {
                isHoveringIsland = isHovering
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

    private var mediaContent: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Gyoza Radio")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Now playing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                mediaButton(systemName: "backward.fill", size: 12) {}

                mediaButton(systemName: isPlaying ? "pause.fill" : "play.fill", size: 16) {
                    isPlaying.toggle()
                }
                .frame(width: 36, height: 36)

                mediaButton(systemName: "forward.fill", size: 12) {}
            }
        }
        .padding(.top, 34)
        .padding(.horizontal, 22)
        .opacity(contentProgress)
        .scaleEffect(lerp(0.98, 1, contentProgress), anchor: .center)
        .clipShape(IslandShellShape(progress: bodyProgress))
        .allowsHitTesting(contentProgress > 0.95)
    }

    private func mediaButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
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
        let bottomRadius = lerp(8, 30, p)

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
        delayedProgress(bodyProgress, start: 0.65)
    }
}
