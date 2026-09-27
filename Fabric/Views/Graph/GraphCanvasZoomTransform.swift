import SwiftUI

/// View-only transform from unscaled canvas coordinates to its fixed layout frame.
/// ScrollView positioning remains outside this transform.
struct GraphCanvasZoomTransform: Equatable
{
    var scale: CGFloat = 1
    var translation: CGSize = .zero

    func canvasPosition(at position: CGPoint) -> CGPoint
    {
        CGPoint(x: (position.x - translation.width) / scale,
                y: (position.y - translation.height) / scale)
    }

    func position(forCanvasPosition position: CGPoint) -> CGPoint
    {
        CGPoint(x: position.x * scale + translation.width,
                y: position.y * scale + translation.height)
    }

    /// Places an unscaled canvas point at a layout-frame point without changing zoom.
    func placing(_ canvasPosition: CGPoint, at position: CGPoint) -> Self
    {
        Self(scale: scale,
             translation: CGSize(width: position.x - canvasPosition.x * scale,
                                 height: position.y - canvasPosition.y * scale))
    }

    /// Magnification is relative to this snapshot, not the preceding gesture update.
    func magnified(by magnification: CGFloat,
                   around anchor: CGPoint,
                   limits: ClosedRange<CGFloat>) -> Self
    {
        let newScale = min(max(scale * magnification, limits.lowerBound), limits.upperBound)
        let anchoredPosition = canvasPosition(at: anchor)

        return Self(scale: newScale).placing(anchoredPosition, at: anchor)
    }
}
