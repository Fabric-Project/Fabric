//
//  StateSubgraphNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Subgraph node with a boolean enable and timed transitions.
///
/// When `Enable` transitions from false→true the subgraph fades in over `In Time` seconds.
/// When it transitions from true→false it fades out over `Out Time` seconds.
/// While fully disabled (enable == false and transition complete) child execution is skipped.
///
/// Place a `State Toggle Info` node inside the subgraph to access progress, elapsed time,
/// and transition state from within the patch.
public class StateSubgraphNode: SubgraphNode {
    public override class var name: String { "State Subgraph" }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeDescription: String { "Subgraph with timed enable/disable transitions. Children stop executing when fully disabled." }

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputEnable", ParameterPort(parameter: BoolParameter("Enable", false, .toggle, "Enable or disable this subgraph"))),
            ("inputInTime", ParameterPort(parameter: FloatParameter("In Time", 1.0, 0.0, 60.0, .inputfield, "Transition duration when enabling (seconds)"))),
            ("inputOutTime", ParameterPort(parameter: FloatParameter("Out Time", 1.0, 0.0, 60.0, .inputfield, "Transition duration when disabling (seconds)"))),
            ("outputActive", NodePort<Float>(name: "Active", kind: .Outlet, description: "Transition intensity: 0 when off, 0→1 during in, 1 when on, 1→0 during out")),
        ]
    }

    // Port proxies
    public var inputEnable: ParameterPort<Bool> { port(named: "inputEnable") }
    public var inputInTime: ParameterPort<Float> { port(named: "inputInTime") }
    public var inputOutTime: ParameterPort<Float> { port(named: "inputOutTime") }
    public var outputActive: NodePort<Float> { port(named: "outputActive") }

    // MARK: - Transition State

    private enum Phase: String {
        case off, transIn, on, transOut
    }

    @ObservationIgnored private var phase: Phase = .off
    @ObservationIgnored private var transitionElapsed: TimeInterval = 0

    // Ensure we always get executed so we can track transitions
    override public var isDirty: Bool { get { true } set { } }

    override public func markClean() {
        if phase != .off {
            super.markClean()
        } else {
            // When disabled the inner subgraph is not executed, so don't
            // cascade markClean into it — that would clear isDirty and
            // valueDidChange on inner nodes that never ran, preventing them
            // from re-executing when the subgraph is later enabled.
            // Only clear our own control ports so edge detection resets.
            inputEnable.valueDidChange = false
            inputInTime.valueDidChange = false
            inputOutTime.valueDidChange = false
            outputActive.valueDidChange = false
        }
    }

    // MARK: - Execution

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer) {
        let dt = context.timing.deltaTime
        let enable = inputEnable.value ?? false
        let inTime = TimeInterval(inputInTime.value ?? 1.0)
        let outTime = TimeInterval(inputOutTime.value ?? 1.0)

        // Detect enable/disable edges
        if inputEnable.valueDidChange {
            if enable && (phase == .off || phase == .transOut) {
                phase = .transIn
                transitionElapsed = 0
            } else if !enable && (phase == .on || phase == .transIn) {
                phase = .transOut
                transitionElapsed = 0
            }
        }

        // Advance transition
        let active: Float

        switch phase {
        case .off:
            active = 0

        case .transIn:
            transitionElapsed += dt
            if inTime <= 0 || transitionElapsed >= inTime {
                transitionElapsed = inTime
                phase = .on
                active = 1
            } else {
                active = Float(transitionElapsed / inTime)
            }

        case .on:
            active = 1

        case .transOut:
            transitionElapsed += dt
            if outTime <= 0 || transitionElapsed >= outTime {
                transitionElapsed = outTime
                phase = .off
                active = 0
            } else {
                active = 1.0 - Float(transitionElapsed / outTime)
            }
        }

        // Send outputs
        outputActive.send(active)

        // Hide subgraph scene when fully off so meshes don't render
        subGraph.scene.visible = phase != .off

        // Only execute children if not fully off
        if phase != .off {
            // Inject toggle info into context for StateInfoNode
            let info = StateToggleInfo(
                intensity: active,
                elapsed: Float(transitionElapsed),
                isIn: phase == .transIn,
                isOn: phase == .on,
                isOut: phase == .transOut
            )
            context.userInfo[StateToggleInfo.contextKey] = info

            // Execute the subgraph
            context.graphRenderer?.execute(
                graph: self.subGraph,
                executionContext: context,
                renderPassDescriptor: renderPassDescriptor,
                commandBuffer: commandBuffer,
                clearFlags: false
            )

            context.userInfo.removeValue(forKey: StateToggleInfo.contextKey)
        }
    }
}

// MARK: - State Toggle Info (context payload)

/// Transition info passed to child nodes via `context.userInfo`.
public struct StateToggleInfo: Hashable {
    public static let contextKey = "stateToggleInfo"

    /// Transition intensity: 0 = fully off, 1 = fully on
    public let intensity: Float
    /// Seconds since the last transition began
    public let elapsed: Float
    /// True during transition in
    public let isIn: Bool
    /// True when fully on
    public let isOn: Bool
    /// True during transition out
    public let isOut: Bool
}
