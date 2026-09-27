import SwiftUI

private struct CenterGraphCanvasKey: EnvironmentKey
{
    static let defaultValue: (CGPoint) -> Void = { _ in }
}

extension EnvironmentValues
{
    /// A view action accepting a graph-space position; no document state is changed.
    var centerGraphCanvas: (CGPoint) -> Void
    {
        get { self[CenterGraphCanvasKey.self] }
        set { self[CenterGraphCanvasKey.self] = newValue }
    }
}

/// Keeps pinch state in the view layer and preserves the canvas point under the pinch.
public struct GraphCanvasZoomModifier: ViewModifier
{
    private let canvasSize: CGSize
    private let allowsContentHitTesting: Bool
    private let zoomLimits: ClosedRange<CGFloat>
    private let commandZoomAnchor: () -> CGPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var committedTransform = GraphCanvasZoomTransform()
    @GestureState(resetTransaction: Transaction(animation: nil))
    private var gestureTransform: GraphCanvasZoomTransform?

    public init(canvasSize: CGSize,
                commandZoomAnchor: @escaping () -> CGPoint,
                allowsContentHitTesting: Bool = true,
                zoomLimits: ClosedRange<CGFloat> = 0.25...2)
    {
        self.canvasSize = canvasSize
        self.commandZoomAnchor = commandZoomAnchor
        self.allowsContentHitTesting = allowsContentHitTesting
        self.zoomLimits = zoomLimits
    }

    public func body(content: Content) -> some View
    {
        let transform = gestureTransform ?? committedTransform

        content
            .environment(\.centerGraphCanvas, center(on:))
            .allowsHitTesting(allowsContentHitTesting && gestureTransform == nil)
            .scaleEffect(transform.scale, anchor: .topLeading)
            .offset(transform.translation)
            // This outer frame stays unscaled, so startLocation is independent
            // of the transform being edited. The gesture itself stays enabled
            // while node/connection hit testing is suspended.
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background {
                GraphBackground(scale: transform.scale, translation: transform.translation)
            }
            .contentShape(.rect)
            .focusedSceneValue(\.graphCanvasZoomActions, GraphCanvasZoomActions(
                zoomIn: gestureTransform == nil && committedTransform.scale < zoomLimits.upperBound
                    ? { zoom(by: 1.25) } : nil,
                zoomOut: gestureTransform == nil && committedTransform.scale > zoomLimits.lowerBound
                    ? { zoom(by: 1 / 1.25) } : nil
            ))
            .gesture(
                MagnifyGesture()
                    .updating($gestureTransform) { value, state, transaction in
                        transaction.animation = nil
                        state = committedTransform.magnified(by: value.magnification,
                                                              around: value.startLocation,
                                                              limits: zoomLimits)
                    }
                    .onEnded { value in
                        committedTransform = committedTransform.magnified(by: value.magnification,
                                                                         around: value.startLocation,
                                                                         limits: zoomLimits)
                    }
            )
    }

    private func zoom(by magnification: CGFloat)
    {
        guard gestureTransform == nil else { return }
        committedTransform = committedTransform.magnified(by: magnification,
                                                         around: commandZoomAnchor(),
                                                         limits: zoomLimits)
    }

    private func center(on graphPosition: CGPoint)
    {
        guard gestureTransform == nil else { return }
        let canvasPosition = CGPoint(x: graphPosition.x + canvasSize.width / 2,
                                     y: graphPosition.y + canvasSize.height / 2)
        // Repeated selections retarget the same spring instead of queuing moves.
        withAnimation(reduceMotion ? nil : .spring(duration: 0.16, bounce: 0))
        {
            committedTransform = committedTransform.placing(canvasPosition, at: commandZoomAnchor())
        }
    }
}
