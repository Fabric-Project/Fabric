//
//  GraphBackground.swift
//  Fabric
//

import SwiftUI

struct GraphBackground: View, Animatable
{
    var scale: CGFloat
    var translation: CGSize
    var image = Image("background")

    // Interpolate the pattern alongside the nodes during animated centering.
    var animatableData: AnimatablePair<CGFloat, CGSize.AnimatableData>
    {
        get { AnimatablePair(scale, translation.animatableData) }
        set
        {
            scale = newValue.first
            translation.animatableData = newValue.second
        }
    }

    var body: some View
    {
        Canvas { context, size in
            // Transform the repeating pattern, not its coverage rectangle.
            // A tiled fill reaches every edge even when the nodes are zoomed out.
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .tiledImage(image,
                                           origin: CGPoint(x: translation.width, y: translation.height),
                                           scale: scale))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
