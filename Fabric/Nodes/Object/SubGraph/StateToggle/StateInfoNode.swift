//
//  StateInfoNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Place inside a State Subgraph to access transition state.
/// Outputs the current progress (0–1), elapsed time since last transition,
/// and individual bool ports for each phase.
public class StateInfoNode: Node {
    public override class var name: String { "State Info" }
    public override class var nodeType: Node.NodeType { .Subgraph }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Reports transition state of the parent State Subgraph node" }

    // Always execute so we pick up every frame's info
    public override var isDirty: Bool { get { true } set { } }

    // Ports
    public let outputActive: NodePort<Float>
    public let outputElapsed: NodePort<Float>
    public let outputIn: NodePort<Bool>
    public let outputOn: NodePort<Bool>
    public let outputOut: NodePort<Bool>
    public override var ports: [Port] { [outputActive, outputElapsed, outputIn, outputOn, outputOut] + super.ports }

    public required init(context: Context) {
        self.outputActive = NodePort<Float>(name: "Active", kind: .Outlet, description: "Transition intensity: 0 when off, 0→1 during in, 1 when on, 1→0 during out")
        self.outputElapsed = NodePort<Float>(name: "Elapsed", kind: .Outlet, description: "Seconds since last transition began")
        self.outputIn = NodePort<Bool>(name: "In", kind: .Outlet, description: "True during transition in")
        self.outputOn = NodePort<Bool>(name: "On", kind: .Outlet, description: "True when fully on")
        self.outputOut = NodePort<Bool>(name: "Out", kind: .Outlet, description: "True during transition out")

        super.init(context: context)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case outputActivePort
        case outputElapsedPort
        case outputInPort
        case outputOnPort
        case outputOutPort
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputActive, forKey: .outputActivePort)
        try container.encode(outputElapsed, forKey: .outputElapsedPort)
        try container.encode(outputIn, forKey: .outputInPort)
        try container.encode(outputOn, forKey: .outputOnPort)
        try container.encode(outputOut, forKey: .outputOutPort)
        try super.encode(to: encoder)
    }

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.outputActive = try container.decode(NodePort<Float>.self, forKey: .outputActivePort)
        self.outputElapsed = try container.decode(NodePort<Float>.self, forKey: .outputElapsedPort)
        self.outputIn = try container.decode(NodePort<Bool>.self, forKey: .outputInPort)
        self.outputOn = try container.decode(NodePort<Bool>.self, forKey: .outputOnPort)
        self.outputOut = try container.decode(NodePort<Bool>.self, forKey: .outputOutPort)
        try super.init(from: decoder)
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        if let info = context.userInfo[StateToggleInfo.contextKey] as? StateToggleInfo {
            outputActive.send(info.intensity)  // intensity doubles as active (0 = off, >0 = active)
            outputElapsed.send(info.elapsed)
            outputIn.send(info.isIn)
            outputOn.send(info.isOn)
            outputOut.send(info.isOut)
        }
    }
}
