import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var panelState: IslandPanelState
    @State private var isHoveringIsland = false
    @State private var expansionProgress: CGFloat = 0

    // The collapsed dimensions come from the detected notch silhouette so the
    // resting pill perfectly overlaps the real notch (or the menu bar on
    // non-notch Macs). Falls back to the published default until a real value
    // is reported.
    private var collapsedWidth: CGFloat { panelState.collapsedSize.width }
    private var collapsedHeight: CGFloat { panelState.collapsedSize.height }
    private let expandedWidth: CGFloat = 300
    private let expandedHeight: CGFloat = 104
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
                .frame(width: 300, height: 118, alignment: .top)
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
        let bottomRadius = lerp(8, 28, p)

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
}
