//
//  BandsVisualizer.swift
//  Fabric
//
//  Shared SwiftUI component for drawing a row of hue-graded vertical bars,
//  optionally highlighting a subset of selected indices and overlaying a
//  per-band "tick" score line. Used by Audio Spectrum, Float Array
//  Dynamics, and Float Array Refiner settings popovers so their
//  visualizations stay visually consistent.
//

import SwiftUI

struct BandsVisualizer: View
{
    let bands: () -> [Float]
    let selected: () -> Set<Int>
    let scores: () -> [Float]
    let onTap: ((Int) -> Void)?

    init(
        bands: @escaping () -> [Float],
        selected: @escaping () -> Set<Int> = { [] },
        scores: @escaping () -> [Float] = { [] },
        onTap: ((Int) -> Void)? = nil
    )
    {
        self.bands = bands
        self.selected = selected
        self.scores = scores
        self.onTap = onTap
    }

    var body: some View
    {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: false)) { timeline in
            GeometryReader { geom in
                Canvas(rendersAsynchronously: false) { ctx, size in
                    // Referencing timeline.date inside the Canvas's capture
                    // scope forces SwiftUI to treat each tick as a distinct
                    // render — without it the Canvas is considered
                    // time-invariant and freezes after the first frame.
                    _ = timeline.date
                    Self.draw(ctx: ctx,
                              size: size,
                              bands: bands(),
                              selected: selected(),
                              scores: scores())
                }
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.35))
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onEnded { value in
                            guard let onTap else { return }
                            let bc = bands().count
                            guard bc > 0, geom.size.width > 0 else { return }
                            let (barWidth, spacing) = Self.barMetrics(width: geom.size.width, count: bc)
                            let i = Int(value.startLocation.x / (barWidth + spacing))
                            guard i >= 0, i < bc else { return }
                            onTap(i)
                        }
                )
            }
        }
    }

    // MARK: - Drawing

    private static func barMetrics(width: CGFloat, count: Int) -> (barWidth: CGFloat, spacing: CGFloat)
    {
        let spacing: CGFloat = count > 64 ? 0 : 1
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let barWidth = max(1, (width - totalSpacing) / CGFloat(count))
        return (barWidth, spacing)
    }

    private static func draw(ctx: GraphicsContext,
                             size: CGSize,
                             bands: [Float],
                             selected: Set<Int>,
                             scores: [Float])
    {
        guard !bands.isEmpty, size.width > 0, size.height > 0 else { return }

        let count = bands.count
        let (barWidth, spacing) = barMetrics(width: size.width, count: count)
        let hasSelection = !selected.isEmpty

        // Bars: hue-graded across the strip. If any selection is present the
        // unselected bars are dimmed; otherwise all bars are fully saturated.
        for i in 0..<count
        {
            let v = CGFloat(max(0, min(1, bands[i])))
            let x = CGFloat(i) * (barWidth + spacing)
            let h = size.height * v
            let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
            let hue = 0.55 - 0.55 * Double(i) / Double(max(1, count - 1))

            let color: Color
            if hasSelection && !selected.contains(i)
            {
                color = Color(hue: hue, saturation: 0.25, brightness: 0.45)
            }
            else
            {
                color = Color(hue: hue, saturation: 0.85, brightness: 1.0)
            }
            ctx.fill(Path(rect), with: .color(color))
        }

        // Score ticks: a single horizontal cap at each band's score height,
        // as though it were the top edge of an invisible bar. Skipped when
        // the scores array doesn't match the bands count — so callers can
        // pass [] to disable the overlay.
        if scores.count == count
        {
            let tickThickness: CGFloat = 1.5
            for i in 0..<count
            {
                let s = CGFloat(max(0, min(1, scores[i])))
                let x = CGFloat(i) * (barWidth + spacing)
                let y = size.height * (1 - s) - tickThickness * 0.5
                let tick = CGRect(x: x, y: y, width: barWidth, height: tickThickness)
                ctx.fill(Path(tick), with: .color(.white.opacity(0.85)))
            }
        }
    }
}
