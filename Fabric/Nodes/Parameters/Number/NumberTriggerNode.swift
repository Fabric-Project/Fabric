//
//  NumberTriggerNode.swift
//  Fabric
//

import Foundation
import SwiftUI
import Satin
import simd
import Metal

public class NumberTriggerNode : Node
{
    override public class var name: String { "Trigger" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Schmitt trigger with minimum on-duration. Output rises to 1 when Target crosses above Trigger Threshold. Output falls back to 0 once Target is below Release Threshold and at least Minimum Duration seconds have elapsed since the rising edge. Hysteresis (Trigger > Release) prevents chatter; Minimum Duration enforces a debounce floor." }

    // Tick every frame so the release condition is detected as time passes,
    // even when the input ports are static.
    public override var isDirty: Bool { get { true } set { } }

    private var state: Float = 0
    private var triggerTime: TimeInterval = 0
    private var hasEmitted: Bool = false

    // Settings popover history. Populated only while showSettings is true so
    // the visualizer doesn't pay the ring-buffer cost when nothing's
    // observing. Capped at `historyCapacity` samples (~3 s @ 60 fps).
    @ObservationIgnored public var visualizationTargetHistory: [Float] = []
    @ObservationIgnored private let historyCapacity: Int = 200

    // Wall-clock timestamp of the last rising-edge fire. Drives the
    // popover's trigger-event indicator; the view reads
    // Date.timeIntervalSinceReferenceDate and computes a fade alpha
    // against this. Always-on (cheap) so the indicator works the moment
    // the popover opens, even if a fire happened just before.
    @ObservationIgnored public var visualizationLastTriggerTime: TimeInterval = 0

    override public func providesSettingsView() -> Bool { true }
    override public func settingsView() -> AnyView { AnyView(NumberTriggerNodeSettingsView(node: self)) }
    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 460, height: 220)) }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTarget", ParameterPort(parameter: FloatParameter("Target", 0.0, .inputfield, "Value being watched"))),
            ("inputTriggerThreshold", ParameterPort(parameter: FloatParameter("Trigger Threshold", 0.8, .inputfield, "Rising-edge threshold: Target at or above this value turns the output to 1"))),
            ("inputReleaseThreshold", ParameterPort(parameter: FloatParameter("Release Threshold", 0.5, .inputfield, "Falling-edge threshold: Target below this value (once Minimum Duration has elapsed) returns the output to 0"))),
            ("inputMinDurationSecs", ParameterPort(parameter: FloatParameter("Minimum Duration (secs)", 0.0, 0.0, 60.0, .inputfield, "Minimum seconds the output must remain 1 before it can fall back to 0"))),
            ("outputValue", NodePort<Float>(name: "Signal", kind: .Outlet, description: "1 while latched high, 0 while latched low")),
        ]
    }

    public var inputTarget: ParameterPort<Float> { port(named: "inputTarget") }
    public var inputTriggerThreshold: ParameterPort<Float> { port(named: "inputTriggerThreshold") }
    public var inputReleaseThreshold: ParameterPort<Float> { port(named: "inputReleaseThreshold") }
    public var inputMinDurationSecs: ParameterPort<Float> { port(named: "inputMinDurationSecs") }
    public var outputValue: NodePort<Float> { port(named: "outputValue") }

    override public func startExecution(context: GraphExecutionContext) {
        self.state = 0
        self.triggerTime = 0
        self.hasEmitted = false
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let now = context.timing.time
        let target = self.inputTarget.value ?? 0
        let triggerThreshold = self.inputTriggerThreshold.value ?? 0
        let releaseThreshold = self.inputReleaseThreshold.value ?? 0
        let minDuration = TimeInterval(self.inputMinDurationSecs.value ?? 0)

        var newState = self.state
        if self.state == 0 {
            if target >= triggerThreshold {
                newState = 1
                self.triggerTime = now
                // Wall-clock stamp for the popover's fire indicator.
                self.visualizationLastTriggerTime = Date.timeIntervalSinceReferenceDate
            }
        } else {
            if target < releaseThreshold && self.triggerTime + minDuration < now {
                newState = 0
            }
        }

        if newState != self.state || !self.hasEmitted {
            self.state = newState
            self.hasEmitted = true
            self.outputValue.send(self.state)
        }

        if self.showSettings {
            if self.visualizationTargetHistory.count >= self.historyCapacity {
                self.visualizationTargetHistory.removeFirst(
                    self.visualizationTargetHistory.count - self.historyCapacity + 1
                )
            }
            self.visualizationTargetHistory.append(target.isFinite ? target : 0)
        }
    }
}

// MARK: - Settings View

private struct NumberTriggerNodeSettingsView: View
{
    @Bindable var node: NumberTriggerNode

    // Y-axis window captured at drag start. Holding it constant for the
    // whole drag prevents the auto-scaling axis from shifting under the
    // user's cursor as they move thresholds — and doubles as an "is the
    // drag in progress?" flag (nil between drags).
    @State private var dragYRange: (yMin: Float, yMax: Float)? = nil

    var body: some View
    {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: false)) { timeline in
            HStack(spacing: 8)
            {
                // Plot lives on the dark scope background.
                GeometryReader { geom in
                    Canvas(rendersAsynchronously: false) { ctx, size in
                        _ = timeline.date
                        Self.drawPlot(
                            ctx: ctx,
                            size: size,
                            history: node.visualizationTargetHistory,
                            triggerThreshold: node.inputTriggerThreshold.value ?? 0.8,
                            releaseThreshold: node.inputReleaseThreshold.value ?? 0.5
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.35))
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                handleDrag(start: value.startLocation,
                                           current: value.location,
                                           size: geom.size)
                            }
                            .onEnded { _ in
                                dragYRange = nil
                            }
                    )
                }

                // Fire indicator sits on the popover's own background, off
                // the dark plot, so it reads as a separate status element.
                Canvas(rendersAsynchronously: false) { ctx, size in
                    _ = timeline.date
                    let elapsed = Date.timeIntervalSinceReferenceDate - node.visualizationLastTriggerTime
                    // Cubic ease-out (1 − t)³: fast initial drop with a
                    // gentle tail, makes the indicator read as a punchy
                    // spike rather than a smooth linear fade.
                    let t = max(0, min(1, elapsed / Self.fireFadeSeconds))
                    let oneMinus = 1 - t
                    let fireAlpha = oneMinus * oneMinus * oneMinus
                    Self.drawIndicator(ctx: ctx, size: size, fireAlpha: fireAlpha)
                }
                .frame(width: 24)
            }
        }
    }

    /// One drag = one rising-edge / falling-edge configuration. The drag's
    /// **start** Y sets the Trigger threshold; the **current** Y sets the
    /// Release threshold (clamped at or below Trigger so the hysteresis
    /// invariant holds). Drag from where the signal should fire to where
    /// it should release.
    private func handleDrag(start: CGPoint, current: CGPoint, size: CGSize)
    {
        guard size.height > 0 else { return }

        // Lock the y-axis at drag start so threshold updates don't shift
        // the mapping mid-drag. Also: set Trigger once, here.
        let yMin: Float
        let yMax: Float
        if let cached = dragYRange
        {
            yMin = cached.yMin
            yMax = cached.yMax
        }
        else
        {
            let range = Self.computeYRange(
                history: node.visualizationTargetHistory,
                trigger: node.inputTriggerThreshold.value ?? 0.8,
                release: node.inputReleaseThreshold.value ?? 0.5
            )
            yMin = range.0
            yMax = range.1
            dragYRange = (yMin, yMax)

            let newTrigger = Self.valueFor(pixel: start.y,
                                           height: size.height,
                                           yMin: yMin, yMax: yMax)
            node.inputTriggerThreshold.value = newTrigger
        }

        let trigger = node.inputTriggerThreshold.value ?? 0.8
        let newRelease = Self.valueFor(pixel: current.y,
                                       height: size.height,
                                       yMin: yMin, yMax: yMax)
        node.inputReleaseThreshold.value = min(newRelease, trigger)
    }

    // MARK: - Geometry helpers (shared between draw + drag)

    private static func computeYRange(history: [Float], trigger: Float, release: Float) -> (Float, Float)
    {
        var minV: Float = 0
        var maxV: Float = 1
        for v in [trigger, release] where v.isFinite
        {
            minV = min(minV, v); maxV = max(maxV, v)
        }
        for v in history where v.isFinite
        {
            minV = min(minV, v); maxV = max(maxV, v)
        }
        let pad = max(0.02, (maxV - minV) * 0.05)
        return (minV - pad, maxV + pad)
    }

    private static func pixelFor(value: Float, height: CGFloat, yMin: Float, yMax: Float) -> CGFloat
    {
        let span = max(0.0001, yMax - yMin)
        let t = CGFloat((value - yMin) / span)
        return height * (1 - t)
    }

    private static func valueFor(pixel: CGFloat, height: CGFloat, yMin: Float, yMax: Float) -> Float
    {
        let t = max(0, min(1, 1 - pixel / max(1, height)))
        return yMin + Float(t) * (yMax - yMin)
    }

    // MARK: - Draw

    private static let indicatorOuterRadius: CGFloat = 9
    private static let indicatorInnerRadius: CGFloat = 6
    private static let fireFadeSeconds: TimeInterval = 0.5

    private static func drawPlot(ctx: GraphicsContext,
                                 size: CGSize,
                                 history: [Float],
                                 triggerThreshold: Float,
                                 releaseThreshold: Float)
    {
        guard size.width > 0, size.height > 0 else { return }

        let labelRightEdge = size.width - 4

        let (yMin, yMax) = computeYRange(history: history,
                                         trigger: triggerThreshold,
                                         release: releaseThreshold)
        let toPixel: (Float) -> CGFloat = { v in
            pixelFor(value: v, height: size.height, yMin: yMin, yMax: yMax)
        }

        // Release threshold line (green, dashed).
        let releaseY = toPixel(releaseThreshold)
        var releasePath = Path()
        releasePath.move(to: CGPoint(x: 0, y: releaseY))
        releasePath.addLine(to: CGPoint(x: size.width, y: releaseY))
        ctx.stroke(releasePath,
                   with: .color(.green.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

        // Trigger threshold line (red, dashed).
        let triggerY = toPixel(triggerThreshold)
        var triggerPath = Path()
        triggerPath.move(to: CGPoint(x: 0, y: triggerY))
        triggerPath.addLine(to: CGPoint(x: size.width, y: triggerY))
        ctx.stroke(triggerPath,
                   with: .color(.red.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

        // Target trace (cyan).
        if history.count > 1
        {
            var path = Path()
            for (i, v) in history.enumerated()
            {
                let x = size.width * CGFloat(i) / CGFloat(history.count - 1)
                let y = toPixel(v.isFinite ? v : 0)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else      { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(.cyan), lineWidth: 1.5)
        }

        // Threshold value labels.
        let triggerText = Text(String(format: "Trigger %.3f", triggerThreshold))
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.red.opacity(0.95))
        let releaseText = Text(String(format: "Release %.3f", releaseThreshold))
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.green.opacity(0.95))

        ctx.draw(triggerText,
                 at: CGPoint(x: labelRightEdge, y: max(10, triggerY - 6)),
                 anchor: .topTrailing)
        ctx.draw(releaseText,
                 at: CGPoint(x: labelRightEdge, y: min(size.height - 4, releaseY + 6)),
                 anchor: .bottomTrailing)
    }

    /// Dim outer ring (always visible) + filled disc whose alpha decays via
    /// cubic ease-out after each rising-edge fire.
    private static func drawIndicator(ctx: GraphicsContext,
                                      size: CGSize,
                                      fireAlpha: Double)
    {
        guard size.width > 0, size.height > 0 else { return }

        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

        let outerRect = CGRect(x: center.x - indicatorOuterRadius,
                               y: center.y - indicatorOuterRadius,
                               width: indicatorOuterRadius * 2,
                               height: indicatorOuterRadius * 2)
        ctx.stroke(Path(ellipseIn: outerRect),
                   with: .color(.secondary.opacity(0.6)),
                   lineWidth: 1)

        let innerRect = CGRect(x: center.x - indicatorInnerRadius,
                               y: center.y - indicatorInnerRadius,
                               width: indicatorInnerRadius * 2,
                               height: indicatorInnerRadius * 2)
        ctx.fill(Path(ellipseIn: innerRect),
                 with: .color(Color.primary.opacity(fireAlpha)))
    }
}
