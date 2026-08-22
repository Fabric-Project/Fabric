//
//  ScopeVisualizer.swift
//  Fabric
//
//  Toward visualising any data type flowing through a graph, rendered
//  performantly with Satin. This is the first pass: scalar numerics only,
//  drawn scope-style with SwiftUI Canvas.
//
//  Shared machinery for oscilloscope-style settings popovers. Nodes push
//  samples through a Combine subject from execute(); the visualisation owns
//  the history — a fixed-capacity ring buffer accumulated on the main
//  thread — and redraws are driven by sample arrival rather than a polling
//  clock. No samples arriving means no work, and the render thread never
//  shares mutable storage with the view.
//
//  Used by the Visualize settings popover directly (ScopeVisualizer), and
//  by the Trigger settings popover, which composes the same ring buffer and
//  ScopePlot helpers with threshold lines and drag interaction.
//

import SwiftUI
import Combine

/// Fixed-capacity rolling sample history. Appends are O(1) with no
/// allocation after init; index 0 is the oldest retained sample.
/// Main-thread only — samples cross from the render thread via the owning
/// view's Combine subscription, not via shared storage.
struct ScopeRingBuffer
{
    private var storage: [Float]
    private var writeIndex: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    /// Default capacity holds ~3 s of samples at 60 fps.
    init(capacity: Int = 200)
    {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: 0, count: self.capacity)
    }

    var isEmpty: Bool { count == 0 }

    var last: Float? {
        count > 0 ? storage[(writeIndex - 1 + capacity) % capacity] : nil
    }

    /// index 0 is the oldest retained sample, count - 1 the newest.
    subscript(_ index: Int) -> Float
    {
        storage[(writeIndex - count + index + capacity) % capacity]
    }

    mutating func append(_ value: Float)
    {
        storage[writeIndex] = value.isFinite ? value : 0
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    mutating func removeAll()
    {
        writeIndex = 0
        count = 0
    }
}

/// Value↔pixel geometry and trace drawing shared by scope-style settings
/// popovers. Keeping the mapping in one place ensures a drag handler and
/// the plot it targets can never disagree about the scale.
enum ScopePlot
{
    /// Auto-scaling y-window: spans at least 0...1, widened to cover the
    /// history and any extra values (e.g. threshold lines), with a small
    /// padding so the trace never sits on the plot edge.
    static func yRange(history: ScopeRingBuffer, including extraValues: [Float] = []) -> (yMin: Float, yMax: Float)
    {
        var minValue: Float = 0
        var maxValue: Float = 1
        for v in extraValues where v.isFinite
        {
            minValue = min(minValue, v); maxValue = max(maxValue, v)
        }
        for i in 0 ..< history.count
        {
            let v = history[i]
            minValue = min(minValue, v); maxValue = max(maxValue, v)
        }
        let padding = max(0.02, (maxValue - minValue) * 0.05)
        return (minValue - padding, maxValue + padding)
    }

    static func pixel(for value: Float, height: CGFloat, yMin: Float, yMax: Float) -> CGFloat
    {
        let span = max(0.0001, yMax - yMin)
        let t = CGFloat((value - yMin) / span)
        return height * (1 - t)
    }

    static func value(atPixel pixelY: CGFloat, height: CGFloat, yMin: Float, yMax: Float) -> Float
    {
        let t = max(0, min(1, 1 - pixelY / max(1, height)))
        return yMin + Float(t) * (yMax - yMin)
    }

    /// Left-to-right trace of the history across the full plot width,
    /// oldest sample at the left edge.
    static func drawTrace(ctx: GraphicsContext,
                          size: CGSize,
                          history: ScopeRingBuffer,
                          yMin: Float,
                          yMax: Float)
    {
        guard history.count > 1, size.width > 0, size.height > 0 else { return }

        var path = Path()
        for i in 0 ..< history.count
        {
            let x = size.width * CGFloat(i) / CGFloat(history.count - 1)
            let y = pixel(for: history[i], height: size.height, yMin: yMin, yMax: yMax)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(path, with: .color(.cyan), lineWidth: 1.5)
    }
}

/// Pure (non-interactive) scope: accumulates pushed samples into its own
/// ring buffer and draws the trace with a latest-value readout. A nil
/// sample means "current value is not plottable" — it clears the trace and
/// the view falls back to `emptyMessage`. Redraws happen only when a
/// sample arrives; an idle input costs nothing.
struct ScopeVisualizer: View
{
    let samples: AnyPublisher<Float?, Never>
    var emptyMessage: String? = nil

    @State private var history = ScopeRingBuffer()

    var body: some View
    {
        ZStack
        {
            if history.isEmpty
            {
                if let emptyMessage
                {
                    Text(emptyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            else
            {
                Canvas(rendersAsynchronously: false) { ctx, size in
                    let (yMin, yMax) = ScopePlot.yRange(history: history)
                    ScopePlot.drawTrace(ctx: ctx, size: size, history: history, yMin: yMin, yMax: yMax)

                    // Y-axis scale: the window's max at top-left, min at
                    // bottom-left. White rather than cyan so the axis reads
                    // apart from the data.
                    let maxLabel = Text(yMax, format: .number.precision(.fractionLength(3)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    ctx.draw(maxLabel,
                             at: CGPoint(x: 4, y: 4),
                             anchor: .topLeading)

                    let minLabel = Text(yMin, format: .number.precision(.fractionLength(3)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    ctx.draw(minLabel,
                             at: CGPoint(x: 4, y: size.height - 4),
                             anchor: .bottomLeading)

                    if let latest = history.last
                    {
                        let readout = Text(latest, format: .number.precision(.fractionLength(3)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.cyan.opacity(0.95))
                        ctx.draw(readout,
                                 at: CGPoint(x: size.width - 4, y: 4),
                                 anchor: .topTrailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.35))
        )
        .onReceive(samples.receive(on: DispatchQueue.main)) { sample in
            if let sample
            {
                history.append(sample)
            }
            else if !history.isEmpty
            {
                history.removeAll()
            }
        }
        .accessibilityLabel("Value history visualizer")
    }
}
