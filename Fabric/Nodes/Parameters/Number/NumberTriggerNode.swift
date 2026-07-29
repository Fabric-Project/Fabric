//
//  NumberTriggerNode.swift
//  Fabric
//

import Foundation
import SwiftUI
import Combine
import Satin
import simd
import Metal

public class NumberTriggerNode : Node
{
    override public class var name: String { "Trigger" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Schmitt trigger with minimum on-duration. Output rises to 1 when Target crosses above Trigger Threshold. Output falls back to 0 once Target is below Release Threshold and at least Minimum Duration seconds have elapsed since the rising edge. Hysteresis (Trigger > Release) prevents chatter; Minimum Duration enforces a debounce floor." }

    // Provider execution mode so the node is evaluated every frame; the
    // minimum-duration release then fires as time passes even while the input
    // ports hold steady.

    private var state: Float = 0
    private var triggerTime: TimeInterval = 0
    private var hasEmitted: Bool = false

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputTarget", ParameterPort(parameter: FloatParameter("Target", 0.0, .inputfield, "Value being watched"))),
            ("inputTriggerThreshold", ParameterPort(parameter: FloatParameter("Trigger Threshold", 0.8, .inputfield, "Rising-edge threshold: Target at or above this value turns the output to 1"))),
            ("inputReleaseThreshold", ParameterPort(parameter: FloatParameter("Release Threshold", 0.5, .inputfield, "Falling-edge threshold: Target below this value (once Minimum Duration has elapsed) returns the output to 0"))),
            ("inputMinDurationSecs", ParameterPort(parameter: FloatParameter("Minimum Duration (secs)", 0.0, 0.0, 60.0, .inputfield, "Minimum seconds the output must remain 1 before it can fall back to 0"))),
            ("outputValue", NodePort<Float>(name: "Trigger", kind: .Outlet, description: "1 while latched high, 0 while latched low")),
        ]
    }

    public var inputTarget: ParameterPort<Float> { port(named: "inputTarget") }
    public var inputTriggerThreshold: ParameterPort<Float> { port(named: "inputTriggerThreshold") }
    public var inputReleaseThreshold: ParameterPort<Float> { port(named: "inputReleaseThreshold") }
    public var inputMinDurationSecs: ParameterPort<Float> { port(named: "inputMinDurationSecs") }
    public var outputValue: NodePort<Float> { port(named: "outputValue") }

    override public func startExecution(renderer: GraphRenderer) throws {
        self.state = 0
        self.triggerTime = 0
        self.hasEmitted = false
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let now = executionInfo.timing.time
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
                self.visualizationFireSubject.send(Date.timeIntervalSinceReferenceDate)
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
            self.visualizationSampleSubject.send(target)
        }
    }

    // MARK: - Visualization

    // Push points for the settings popover, which owns the sample history
    // (see ScopeVisualizer.swift). execute() pushes one Target sample per
    // frame only while the popover is observing, keeping the closed-popover
    // steady state zero-work.
    public let visualizationSampleSubject = PassthroughSubject<Float, Never>()

    // Wall-clock timestamp of the last rising-edge fire. CurrentValueSubject
    // so a subscriber arriving just after a fire still sees it and can show
    // the fade. Always stamped (cheap) so the indicator works the moment the
    // popover opens.
    public let visualizationFireSubject = CurrentValueSubject<TimeInterval, Never>(0)

    override public func providesSettingsView() -> Bool { true }

    final class SettingsModel {
        weak var node: NumberTriggerNode?
        init(node: NumberTriggerNode) { self.node = node }

        var triggerThreshold: Float {
            get { node?.inputTriggerThreshold.value ?? 0.8 }
            set { node?.inputTriggerThreshold.value = newValue }
        }
        var releaseThreshold: Float {
            get { node?.inputReleaseThreshold.value ?? 0.5 }
            set { node?.inputReleaseThreshold.value = newValue }
        }

        /// Called once per plot gesture, before the first threshold write, so
        /// the whole gesture (a click or a full drag) undoes as one step back
        /// to the pre-gesture configuration.
        func registerThresholdUndo() {
            guard let node else { return }
            let previousTrigger = node.inputTriggerThreshold.value ?? 0.8
            let previousRelease = node.inputReleaseThreshold.value ?? 0.5
            node.graph?.undoManager?.registerUndo(withTarget: node) { node in
                node.restoreThresholds(trigger: previousTrigger, release: previousRelease)
            }
            node.graph?.undoManager?.setActionName("Set Trigger Thresholds")
        }
    }

    /// Undo target: restores both thresholds, re-registering the values being
    /// replaced so undo/redo can toggle between the two configurations.
    func restoreThresholds(trigger: Float, release: Float) {
        let replacedTrigger = self.inputTriggerThreshold.value ?? 0.8
        let replacedRelease = self.inputReleaseThreshold.value ?? 0.5
        self.graph?.undoManager?.registerUndo(withTarget: self) { node in
            node.restoreThresholds(trigger: replacedTrigger, release: replacedRelease)
        }
        self.graph?.undoManager?.setActionName("Set Trigger Thresholds")
        self.inputTriggerThreshold.value = trigger
        self.inputReleaseThreshold.value = release
    }

    private lazy var _settingsModel = SettingsModel(node: self)

    override public func settingsView() -> AnyView
    {
        AnyView(NumberTriggerNodeSettingsView(
            model: _settingsModel,
            samples: visualizationSampleSubject.eraseToAnyPublisher(),
            fires: visualizationFireSubject.eraseToAnyPublisher()
        ))
    }

    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 460, height: 220)) }
}

// MARK: - Settings View

private struct NumberTriggerNodeSettingsView: View
{
    let model: NumberTriggerNode.SettingsModel
    let samples: AnyPublisher<Float, Never>
    let fires: AnyPublisher<TimeInterval, Never>

    // Rolling Target history, owned by the view and fed by the node's push
    // subject — the render thread never shares mutable storage with us.
    @State private var history = ScopeRingBuffer()

    // Y-axis window captured at drag start. Holding it constant for the
    // whole drag prevents the auto-scaling axis from shifting under the
    // user's cursor as they move thresholds — and doubles as an "is the
    // drag in progress?" flag (nil between drags).
    @State private var dragYRange: (yMin: Float, yMax: Float)? = nil

    // Latest drag-set release value. The thresholds live on ports, which
    // aren't observable, so this write is what invalidates the plot on each
    // drag change — without it the threshold lines would freeze mid-drag
    // whenever the graph is stopped and no samples are arriving.
    @State private var dragValue: Float? = nil

    // Plot canvas size, captured via onGeometryChange so the drag handler
    // doesn't need a wrapping GeometryReader.
    @State private var plotSize: CGSize = .zero

    // Timestamp of the fire the indicator is currently fading out from.
    @State private var indicatorFireTime: TimeInterval = 0

    var body: some View
    {
        HStack(spacing: 8)
        {
            // Plot lives on the dark scope background.
            Canvas(rendersAsynchronously: false) { ctx, size in
                Self.drawPlot(
                    ctx: ctx,
                    size: size,
                    history: history,
                    triggerThreshold: model.triggerThreshold,
                    releaseThreshold: model.releaseThreshold,
                    lockedRange: dragYRange
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.35))
            )
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                plotSize = newSize
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        handleDrag(start: value.startLocation,
                                   current: value.location,
                                   size: plotSize)
                    }
                    .onEnded { _ in
                        dragYRange = nil
                        dragValue = nil
                    }
            )
            .accessibilityLabel("Trigger threshold visualizer")
            .accessibilityHint("Drag to set the trigger threshold at the start point and the release threshold at the end point.")

            // Fire indicator sits on the popover's own background, off
            // the dark plot, so it reads as a separate status element.
            TriggerFireIndicator(fireTime: indicatorFireTime)
                .frame(width: 24)
                .accessibilityLabel("Trigger fire indicator")
        }
        .onReceive(samples.receive(on: DispatchQueue.main)) { sample in
            history.append(sample)
        }
        .onReceive(fires.receive(on: DispatchQueue.main)) { fireTime in
            // Ignore stale fires (including the subject's initial 0) so
            // opening the popover long after a fire doesn't flash the
            // indicator; a recent fire replays as a full fade.
            guard Date.timeIntervalSinceReferenceDate - fireTime < TriggerFireIndicator.fadeSeconds else { return }
            indicatorFireTime = fireTime
        }
    }

    /// One drag = one rising-edge / falling-edge configuration. The drag's
    /// **start** Y sets the Trigger threshold; the **current** Y sets the
    /// Release threshold (clamped at or below Trigger so the hysteresis
    /// invariant holds). Drag from where the signal should fire to where
    /// it should release. A plain click sets both to the click point
    /// (zero hysteresis); the whole gesture is one undo step.
    private func handleDrag(start: CGPoint, current: CGPoint, size: CGSize)
    {
        guard size.height > 0 else { return }

        // Lock the y-axis at drag start so threshold updates don't shift
        // the mapping mid-drag. Also: register undo and set Trigger once, here.
        let yMin: Float
        let yMax: Float
        if let cached = dragYRange
        {
            yMin = cached.yMin
            yMax = cached.yMax
        }
        else
        {
            let range = ScopePlot.yRange(
                history: history,
                including: [model.triggerThreshold, model.releaseThreshold]
            )
            yMin = range.yMin
            yMax = range.yMax
            dragYRange = (yMin, yMax)

            model.registerThresholdUndo()
            model.triggerThreshold = ScopePlot.value(atPixel: start.y,
                                                     height: size.height,
                                                     yMin: yMin, yMax: yMax)
        }

        let newRelease = ScopePlot.value(atPixel: current.y,
                                         height: size.height,
                                         yMin: yMin, yMax: yMax)
        let clampedRelease = min(newRelease, model.triggerThreshold)
        model.releaseThreshold = clampedRelease
        dragValue = clampedRelease
    }

    // MARK: - Draw

    private static func drawPlot(ctx: GraphicsContext,
                                 size: CGSize,
                                 history: ScopeRingBuffer,
                                 triggerThreshold: Float,
                                 releaseThreshold: Float,
                                 lockedRange: (yMin: Float, yMax: Float)?)
    {
        guard size.width > 0, size.height > 0 else { return }

        let labelRightEdge = size.width - 4

        // While a drag is in progress the plot renders with the drag's frozen
        // y-window: the handler and the drawing must share one scale, or the
        // threshold lines drift away from the cursor as the live history
        // rescales the axis. Samples outside the frozen window draw clipped
        // until the drag ends.
        let (yMin, yMax) = lockedRange
            ?? ScopePlot.yRange(history: history,
                                including: [triggerThreshold, releaseThreshold])
        let toPixel: (Float) -> CGFloat = { v in
            ScopePlot.pixel(for: v, height: size.height, yMin: yMin, yMax: yMax)
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
        ScopePlot.drawTrace(ctx: ctx, size: size, history: history, yMin: yMin, yMax: yMax)

        // Threshold value labels.
        let triggerText = Text("Trigger \(triggerThreshold, format: .number.precision(.fractionLength(3)))")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.red.opacity(0.95))
        let releaseText = Text("Release \(releaseThreshold, format: .number.precision(.fractionLength(3)))")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.green.opacity(0.95))

        ctx.draw(triggerText,
                 at: CGPoint(x: labelRightEdge, y: max(10, triggerY - 6)),
                 anchor: .topTrailing)
        ctx.draw(releaseText,
                 at: CGPoint(x: labelRightEdge, y: min(size.height - 4, releaseY + 6)),
                 anchor: .bottomTrailing)
    }
}

/// Dim outer ring (always visible) + filled disc that flashes on and fades
/// out after each rising-edge fire. The keyframe animator runs one fade per
/// fire timestamp and then stops — no polling clock, so an idle indicator
/// costs nothing.
private struct TriggerFireIndicator: View
{
    static let fadeSeconds: TimeInterval = 0.5

    let fireTime: TimeInterval

    var body: some View
    {
        ZStack
        {
            Circle()
                .stroke(.secondary.opacity(0.6), lineWidth: 1)
                .frame(width: 18, height: 18)

            Circle()
                .fill(.primary)
                .frame(width: 12, height: 12)
                .keyframeAnimator(initialValue: 0.0, trigger: fireTime) { view, alpha in
                    view.opacity(alpha)
                } keyframes: { _ in
                    // Punchy spike: instant flash to full, then a fast
                    // ease-out fall with a gentle tail.
                    LinearKeyframe(1.0, duration: 0.02)
                    CubicKeyframe(0.0, duration: Self.fadeSeconds)
                }
        }
    }
}
