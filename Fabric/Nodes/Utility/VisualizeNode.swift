//
//  VisualizeNode.swift
//  Fabric
//

import Foundation
import SwiftUI
import Combine
import Satin
import simd
import Metal

/// Sibling of the Log node: where Log prints values to the console, this
/// node plots them. The goal is to visualise any data type flowing through
/// a graph, rendered performantly with Satin; this first pass draws an
/// oscilloscope-style SwiftUI trace whenever the input unboxes to a scalar
/// numeric.
public class VisualizeNode : Node
{
    override public class var name: String { "Visualize" }
    override public class var nodeType: Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Plot values over time. Open Settings for an oscilloscope-style trace of any Boolean, Integer or Float value." }

    // Ports
    public let inputAny: NodePort<PortValue>
    public override var ports: [Port] { [self.inputAny] + super.ports }

    public required init(context: Context)
    {
        self.inputAny = NodePort<PortValue>(name: "Value", kind: .Inlet, description: "Value to plot")

        super.init(context: context)
    }

    enum CodingKeys : String, CodingKey
    {
        case inputAnyPort
    }

    public override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.inputAny, forKey: .inputAnyPort)

        try super.encode(to: encoder)
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAny = try container.decode(NodePort<PortValue>.self, forKey: .inputAnyPort)

        try super.init(from: decoder)
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.showSettings
        {
            // Sampled every frame — not just on valueDidChange — so the
            // trace scrolls in time like a scope. nil (no value, or a
            // non-numeric type) tells the visualizer to clear its trace
            // and fall back to the empty-state message.
            self.visualizationSampleSubject.send(self.inputAny.value.flatMap(Self.numericValue(from:)))
        }
    }

    // MARK: - Visualization

    // Push point for the settings popover, which owns the sample history
    // (see ScopeVisualizer.swift). execute() pushes one sample per frame
    // only while the popover is observing, keeping the closed-popover
    // steady state zero-work.
    public let visualizationSampleSubject = PassthroughSubject<Float?, Never>()

    /// Unboxes the scalar numeric PortValue cases for the scope. Bool
    /// plots as 0/1 so pulse streams read as square waves; everything
    /// else (String, vectors, textures…) is not plottable.
    private static func numericValue(from value: PortValue) -> Float?
    {
        switch value
        {
        case .Bool(let boolValue):   return boolValue ? 1 : 0
        case .Int(let intValue):     return Float(intValue)
        case .Float(let floatValue): return floatValue
        default:                     return nil
        }
    }

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        AnyView(ScopeVisualizer(samples: visualizationSampleSubject.eraseToAnyPublisher(),
                                emptyMessage: "Connect a Boolean, Integer or Float value to plot it here"))
    }

    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 460, height: 160)) }
}
