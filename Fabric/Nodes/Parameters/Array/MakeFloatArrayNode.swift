//
//  MakeFloatArrayNode.swift
//  Fabric
//

import SwiftUI
import Satin
import simd
import Metal

// MARK: - Settings View

struct MakeFloatArrayNodeSettingsView: View {
    @Bindable var node: MakeFloatArrayNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Count")
                    .font(.system(size: 10))
                Spacer()
                Stepper("\(node.count)", value: Binding(
                    get: { node.count },
                    set: { node.setCount($0) }
                ), in: 0...32)
                .font(.system(size: 10))
            }
        }
        .padding(4)
    }
}

// MARK: - Make Float Array Node

@Observable public class MakeFloatArrayNode: Node
{
    public override class var name: String { "Make Float Array" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Assembles N Float values into a Float array. Count is set in the node settings and determines how many editable Value input ports appear." }

    // Static output port only; value ports are dynamic.
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return ports + [
            ("outputArray", NodePort<ContiguousArray<Float>>(name: "Array", kind: .Outlet, description: "Array assembled from the Value inputs, in order")),
        ]
    }

    public var outputArray: NodePort<ContiguousArray<Float>> { port(named: "outputArray") }

    // MARK: - Configurable state

    fileprivate(set) var count: Int = 2 {
        didSet { if oldValue != count { rebuildPorts() } }
    }

    @ObservationIgnored private var outputDirty: Bool = true

    public func setCount(_ newValue: Int) {
        let clamped = max(0, min(newValue, 32))
        guard clamped != count else { return }
        count = clamped
    }

    // MARK: - Init

    public required init(context: Context) {
        super.init(context: context)
        rebuildPorts()
    }

    // MARK: - Codable

    private enum MakeFloatArrayCodingKeys: String, CodingKey {
        case count
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        let container = try decoder.container(keyedBy: MakeFloatArrayCodingKeys.self)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 2
        rebuildPorts()
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: MakeFloatArrayCodingKeys.self)
        try container.encode(count, forKey: .count)
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }
    override public func settingsView() -> AnyView { AnyView(MakeFloatArrayNodeSettingsView(node: self)) }

    // MARK: - Dynamic ports

    private static func portKey(_ i: Int) -> String { "inputValue\(i)" }

    private func rebuildPorts() {
        // Find current dynamic input port count by probing keys.
        var existingCount = 0
        while findPort(named: Self.portKey(existingCount)) != nil {
            existingCount += 1
        }

        // Remove excess ports (from the end).
        if existingCount > count {
            for i in stride(from: existingCount - 1, through: count, by: -1) {
                if let p: Port = findPort(named: Self.portKey(i)) {
                    removePort(p)
                }
            }
        }

        // Add missing ports.
        for i in existingCount..<count {
            let port = ParameterPort(parameter: FloatParameter("Value \(i)", 0.0, .inputfield, "Value at index \(i)"))
            addDynamicPort(port, name: Self.portKey(i))
        }

        outputDirty = true
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let anyInputChanged = self.inputPorts().contains(where: { $0.valueDidChange })
        guard anyInputChanged || self.outputDirty else { return }
        self.outputDirty = false

        var output = ContiguousArray<Float>()
        output.reserveCapacity(count)
        for i in 0..<count {
            if let port: ParameterPort<Float> = self.findPort(named: Self.portKey(i)),
               let value = port.value
            {
                output.append(value)
            }
            else
            {
                output.append(0)
            }
        }
        self.outputArray.send(output)
    }
}
