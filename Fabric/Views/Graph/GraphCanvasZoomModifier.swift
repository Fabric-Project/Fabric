import SwiftUI

/// Keeps pinch state in the view layer and preserves the canvas point under the pinch.
public struct GraphCanvasZoomModifier: ViewModifier
{
    private let canvasSize: CGSize
    private let allowsContentHitTesting: Bool
    private let zoomLimits: ClosedRange<CGFloat>

    @State private var committedTransform = GraphCanvasZoomTransform()
    @GestureState(resetTransaction: Transaction(animation: nil))
    private var gestureTransform: GraphCanvasZoomTransform?

    public init(canvasSize: CGSize,
                allowsContentHitTesting: Bool = true,
                zoomLimits: ClosedRange<CGFloat> = 0.25...2)
    {
        self.canvasSize = canvasSize
        self.allowsContentHitTesting = allowsContentHitTesting
        self.zoomLimits = zoomLimits
    }

    public func body(content: Content) -> some View
    {
        let transform = gestureTransform ?? committedTransform

        content
            .allowsHitTesting(allowsContentHitTesting && gestureTransform == nil)
            .scaleEffect(transform.scale, anchor: .topLeading)
            .offset(transform.translation)
            // This outer frame stays unscaled, so startLocation is independent
            // of the transform being edited. The gesture itself stays enabled
            // while node/connection hit testing is suspended.
            .frame(width: canvasSize.width, height: canvasSize.height)
            .contentShape(.rect)
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
}
