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
        .contentShape(IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress, topWidth: collapsedWidth, bandHeight: panelState.bandHeight))
        .onHover { isHovering in
            if isHovering != isHoveringIsland {
                isHoveringIsland = isHovering
            }
        }
    }

    private var islandShadow: some View {
        IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress, topWidth: collapsedWidth, bandHeight: panelState.bandHeight)
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
        IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress, topWidth: collapsedWidth, bandHeight: panelState.bandHeight)
            .fill(Color.black)
            .overlay(
                IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress, topWidth: collapsedWidth, bandHeight: panelState.bandHeight)
                    .stroke(Color.white.opacity(lerp(0.015, 0.08, bodyProgress)), lineWidth: 1)
            )
    }
}

private struct IslandShellShape: Shape {
    var progress: CGFloat
    var shoulderProgress: CGFloat
    /// Width of the real notch silhouette. The top portion of the shape stays
    /// pinned to this width regardless of how wide `rect` becomes during
    /// expansion, so the expanded card looks like it grows out *from beneath*
    /// the notch instead of replacing it with a wider pill.
    var topWidth: CGFloat
    /// Height of the menu bar reserve (notch height + any extra strip below
    /// it). The flare ends here so the wider card body begins exactly at the
    /// menu bar's bottom edge — making the expanded card visually "drip" out
    /// of the menu bar instead of floating below it.
    var bandHeight: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, shoulderProgress) }
        set {
            progress = newValue.first
            shoulderProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1)
        let s = min(max(shoulderProgress, 0), 1)
        let shoulderInset = lerp(18, 17.6, s)
        let shoulderDepth = lerp(4, 4.8, s)
        let bottomCornerRadius = lerp(8, 28, p)
        let topControlInset = lerp(2, 2.5, s)
        let shoulderControlDepth = lerp(1.5, 1.9, s)

        // The notch occupies a fixed-width band centered horizontally in the
        // rect. Any extra rect width is the flare region that sits *below* the
        // notch shoulders.
        let clampedTopWidth = min(max(topWidth, 0), rect.width)
        let topMinX = rect.midX - clampedTopWidth / 2
        let topMaxX = rect.midX + clampedTopWidth / 2

        let topLeft = CGPoint(x: topMinX + shoulderInset, y: rect.minY)
        let topRight = CGPoint(x: topMaxX - shoulderInset, y: rect.minY)
        let rightShoulder = CGPoint(x: topMaxX, y: rect.minY + shoulderDepth)
        let leftShoulder = CGPoint(x: topMinX, y: rect.minY + shoulderDepth)

        // The flare lands at the menu bar's bottom edge. From there the wider
        // card body extends downward — visually attached to the menu bar.
        // Falls back to zero when collapsed so the resting silhouette is
        // unchanged.
        let flareEndY = max(shoulderDepth, bandHeight)
        let flareDepth = lerp(0, flareEndY - shoulderDepth, p)
        let rightFlareEnd = CGPoint(x: rect.maxX, y: rect.minY + shoulderDepth + flareDepth)
        let leftFlareEnd = CGPoint(x: rect.minX, y: rect.minY + shoulderDepth + flareDepth)

        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)

        // Right notch shoulder (curve from flat top down into the notch's
        // rounded outer corner — same silhouette as the real hardware notch).
        path.addCurve(
            to: rightShoulder,
            control1: CGPoint(x: topMaxX - topControlInset, y: rect.minY),
            control2: CGPoint(x: topMaxX, y: rect.minY + shoulderControlDepth)
        )

        // Right flare: smooth S-curve from the notch shoulder outward to the
        // expanded card's right wall. Degenerates to nothing when collapsed.
        path.addCurve(
            to: rightFlareEnd,
            control1: CGPoint(x: topMaxX, y: rect.minY + shoulderDepth + flareDepth / 2),
            control2: CGPoint(x: rect.maxX, y: rect.minY + shoulderDepth + flareDepth / 2)
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomCornerRadius))
        path.addArc(
            center: CGPoint(
                x: rect.maxX - bottomCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            radius: bottomCornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(
                x: rect.minX + bottomCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            radius: bottomCornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.addLine(to: leftFlareEnd)

        // Left flare: mirror of the right flare, curving inward from the wall
        // up to the notch's left shoulder.
        path.addCurve(
            to: leftShoulder,
            control1: CGPoint(x: rect.minX, y: rect.minY + shoulderDepth + flareDepth / 2),
            control2: CGPoint(x: topMinX, y: rect.minY + shoulderDepth + flareDepth / 2)
        )

        path.addCurve(
            to: topLeft,
            control1: CGPoint(x: topMinX, y: rect.minY + shoulderControlDepth),
            control2: CGPoint(x: topMinX + topControlInset, y: rect.minY)
        )
        path.closeSubpath()
        return path
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
    // so these properties pass through without the previous cubic ease-out.
    // Double-easing flattened the spring's overshoot.
    var bodyProgress: CGFloat {
        shapeProgress
    }

    var shoulderProgress: CGFloat {
        delayedProgress(shapeProgress, start: 0.34)
    }

    // Delay the shadow until the pill is meaningfully extended; at rest the
    // pill has no shadow so it blends with the real notch.
    var shadowProgress: CGFloat {
        delayedProgress(bodyProgress, start: 0.45)
    }
}
