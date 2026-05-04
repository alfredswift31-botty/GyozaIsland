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
    private let hoverInAnimation = Animation.linear(duration: 0.22)
    private let hoverOutAnimation = Animation.linear(duration: 0.26)

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
        .contentShape(IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress))
        .onHover { isHovering in
            if isHovering != isHoveringIsland {
                isHoveringIsland = isHovering
            }
        }
    }

    private var islandShadow: some View {
        IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress)
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
        IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress)
            .fill(Color.black)
            .overlay(
                IslandShellShape(progress: bodyProgress, shoulderProgress: shoulderProgress)
                    .stroke(Color.white.opacity(lerp(0.015, 0.08, bodyProgress)), lineWidth: 1)
            )
    }
}

private struct IslandShellShape: Shape {
    var progress: CGFloat
    var shoulderProgress: CGFloat

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

        let topLeft = CGPoint(x: rect.minX + shoulderInset, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - shoulderInset, y: rect.minY)
        let rightShoulder = CGPoint(x: rect.maxX, y: rect.minY + shoulderDepth)
        let leftShoulder = CGPoint(x: rect.minX, y: rect.minY + shoulderDepth)

        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addCurve(
            to: rightShoulder,
            control1: CGPoint(x: rect.maxX - topControlInset, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + shoulderControlDepth)
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
        path.addLine(to: leftShoulder)
        path.addCurve(
            to: topLeft,
            control1: CGPoint(x: rect.minX, y: rect.minY + shoulderControlDepth),
            control2: CGPoint(x: rect.minX + topControlInset, y: rect.minY)
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
    var bodyProgress: CGFloat {
        easedProgress(shapeProgress)
    }

    var shoulderProgress: CGFloat {
        easedProgress(delayedProgress(shapeProgress, start: 0.34))
    }

    var shadowProgress: CGFloat {
        delayedProgress(bodyProgress, start: 0.22)
    }
}

private func easedProgress(_ progress: CGFloat) -> CGFloat {
    let clamped = min(max(progress, 0), 1)
    return 1 - pow(1 - clamped, 3)
}
