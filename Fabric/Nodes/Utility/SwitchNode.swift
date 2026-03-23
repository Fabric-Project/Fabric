//
//  SwitchNode.swift
//  Fabric
//

import SwiftUI
import Satin
import Metal

// MARK: - Settings View

struct SwitchNodeSettingsView: View {
    @Bindable var node: SwitchNode

    private let typeOptions: [(label: String, type: PortType)] = [
        ("Any",       .Virtual),
        ("Bool",      .Bool),
        ("Int",       .Int),
        ("Float",     .Float),
        ("String",    .String),
        ("Vector 2",  .Vector2),
        ("Vector 3",  .Vector3),
        ("Vector 4",  .Vector4),
        ("Color",     .Color),
        ("Image",     .Image),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Inputs")
                    .font(.system(size: 10))
                Spacer()
                Stepper("\(node.inputCount)", value: Binding(
                    get: { node.inputCount },
                    set: { node.setInputCount($0) }
                ), in: 2...16)
                .font(.system(size: 10))
            }

            HStack {
                Text("Type")
                    .font(.system(size: 10))
                Spacer()
                Picker("", selection: Binding(
                    get: { node.portValueType.rawValue },
                    set: { raw in
                        if let pt = PortType(rawValue: raw) {
                            node.setPortType(pt)
                        }
                    }
                )) {
                    ForEach(typeOptions, id: \.label) { option in
                        Text(option.label).tag(option.type.rawValue)
                    }
                }
                .frame(width: 100)
                .font(.system(size: 10))
            }
        }
        .padding(4)
    }
}

// MARK: - Switch Node

@Observable public class SwitchNode: Node {
    override public class var name: String { "Switch" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Select one of several inputs to pass through. Only the selected branch is evaluated." }

    // Ports — only the index port is registered statically; value ports are dynamic.
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return ports + [
            ("inputIndex", ParameterPort(parameter: IntParameter("Index", 0, 0, 1, .inputfield, "Which input to select"))),
        ]
    }

    // MARK: - Configurable State

    fileprivate(set) var inputCount: Int = 2 {
        didSet { rebuildPorts() }
    }

    fileprivate(set) var portValueType: PortType = .Virtual {
        didSet { rebuildPorts() }
    }

    // MARK: - Init

    public required init(context: Context) {
        super.init(context: context)
        rebuildPorts()
    }

    // MARK: - Codable

    private enum SwitchCodingKeys: String, CodingKey {
        case inputCount
        case portValueType
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: SwitchCodingKeys.self)
        self.inputCount = try container.decodeIfPresent(Int.self, forKey: .inputCount) ?? 2
        self.portValueType = try container.decodeIfPresent(PortType.self, forKey: .portValueType) ?? .Virtual

        rebuildPorts()
    }

    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: SwitchCodingKeys.self)
        try container.encode(inputCount, forKey: .inputCount)
        try container.encode(portValueType, forKey: .portValueType)
    }

    // MARK: - Settings

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView {
        AnyView(SwitchNodeSettingsView(node: self))
    }

    // MARK: - Public Setters (called from settings view)

    func setInputCount(_ count: Int) {
        let clamped = max(2, min(count, 16))
        guard clamped != inputCount else { return }
        inputCount = clamped
    }

    func setPortType(_ type: PortType) {
        guard type != portValueType else { return }
        portValueType = type
    }

    // MARK: - Dynamic Port Management

    /// Registry key for value input port at index i
    private static func inputKey(_ i: Int) -> String { "input\(i)" }
    private static let outputKey = "output"

    private func rebuildPorts() {
        // Update index parameter range
        if let param = inputIndex.parameter as? IntParameter {
            param.max = inputCount - 1
        }

        // Find the range of input ports that currently exist
        var existingCount = 0
        while findPort(named: Self.inputKey(existingCount)) != nil {
            existingCount += 1
        }

        // Remove excess input ports (from the end)
        for i in stride(from: existingCount - 1, through: inputCount, by: -1) {
            if let p: Port = findPort(named: Self.inputKey(i)) {
                removePort(p)
            }
        }

        // Add or replace input ports
        for i in 0..<inputCount {
            let key = Self.inputKey(i)
            let displayName = "Input \(i)"
            if let existing: Port = findPort(named: key) {
                // Replace if type changed
                if existing.portType != portValueType {
                    removePort(existing)
                    addDynamicPort(makePort(name: displayName, kind: .Inlet), name: key)
                }
            } else {
                addDynamicPort(makePort(name: displayName, kind: .Inlet), name: key)
            }
        }

        // Rebuild output port if needed
        if let existing: Port = findPort(named: Self.outputKey) {
            if existing.portType != portValueType {
                removePort(existing)
                addDynamicPort(makePort(name: "Output", kind: .Outlet), name: Self.outputKey)
            }
        } else {
            addDynamicPort(makePort(name: "Output", kind: .Outlet), name: Self.outputKey)
        }
    }

    private func makePort(name: String, kind: PortKind) -> Port {
        let desc = kind == .Inlet ? "Switch input" : "The selected input value"

        // Outlets and Virtual inputs use NodePort (no inspector widget)
        if kind == .Outlet || portValueType == .Virtual {
            return makeNodePort(name: name, kind: kind, description: desc)
        }

        // Typed inlets use ParameterPort for inspector editing
        switch portValueType {
        case .Bool:    return ParameterPort(parameter: BoolParameter(name, false, .button, desc))
        case .Int:     return ParameterPort(parameter: IntParameter(name, 0, .inputfield, desc))
        case .Float:   return ParameterPort(parameter: FloatParameter(name, 0, .inputfield, desc))
        case .String:  return ParameterPort(parameter: StringParameter(name, "", .inputfield, desc))
        case .Vector2: return ParameterPort(parameter: Float2Parameter(name, .zero, .inputfield, desc))
        case .Vector3: return ParameterPort(parameter: Float3Parameter(name, .zero, .inputfield, desc))
        case .Vector4: return ParameterPort(parameter: Float4Parameter(name, .zero, .inputfield, desc))
        case .Color:   return ParameterPort(parameter: Float4Parameter(name, .zero, .colorpicker, desc))
        default:       return makeNodePort(name: name, kind: kind, description: desc)
        }
    }

    private func makeNodePort(name: String, kind: PortKind, description: String) -> Port {
        switch portValueType {
        case .Bool:       return NodePort<Swift.Bool>(name: name, kind: kind, description: description)
        case .Int:        return NodePort<Swift.Int>(name: name, kind: kind, description: description)
        case .Float:      return NodePort<Swift.Float>(name: name, kind: kind, description: description)
        case .String:     return NodePort<Swift.String>(name: name, kind: kind, description: description)
        case .Vector2:    return NodePort<simd_float2>(name: name, kind: kind, description: description)
        case .Vector3:    return NodePort<simd_float3>(name: name, kind: kind, description: description)
        case .Vector4:    return NodePort<simd_float4>(name: name, kind: kind, description: description)
        case .Color:      return NodePort<simd_float4>(name: name, kind: kind, description: description)
        case .Image:      return NodePort<FabricImage>(name: name, kind: kind, description: description)
        default:          return NodePort<PortValue>(name: name, kind: kind, description: description)
        }
    }

    // MARK: - Port Accessors

    public var inputIndex: ParameterPort<Int> { port(named: "inputIndex") }

    private var selectedInputPort: Port {
        let index = max(0, min(inputIndex.value ?? 0, inputCount - 1))
        return findPort(named: Self.inputKey(index))
            ?? findPort(named: Self.inputKey(0))!
    }

    private var outputPort: Port {
        findPort(named: Self.outputKey)!
    }

    // MARK: - Conditional Evaluation

    /// Only pull the upstream node connected to the selected input port.
    /// The index port's upstream is always pulled so the selector stays live.
    open override func activeInputNodes() -> [Node] {
        var nodes: [Node] = []

        // Always pull the index input's upstream
        for connection in inputIndex.connections {
            if let node = connection.node { nodes.append(node) }
        }

        // Pull only the selected value input's upstream
        for connection in selectedInputPort.connections {
            if let node = connection.node, !nodes.contains(node) { nodes.append(node) }
        }

        return nodes
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        // When the port type is known, use the typed path to avoid the
        // PortValue box/unbox overhead (indirect enum heap allocation).
        switch portValueType {
        case .Image:
            forwardTyped(selectedInputPort, to: outputPort, as: FabricImage.self)
        case .Bool:
            forwardTyped(selectedInputPort, to: outputPort, as: Bool.self)
        case .Int:
            forwardTyped(selectedInputPort, to: outputPort, as: Int.self)
        case .Float:
            forwardTyped(selectedInputPort, to: outputPort, as: Float.self)
        case .String:
            forwardTyped(selectedInputPort, to: outputPort, as: String.self)
        case .Vector2:
            forwardTyped(selectedInputPort, to: outputPort, as: simd_float2.self)
        case .Vector3:
            forwardTyped(selectedInputPort, to: outputPort, as: simd_float3.self)
        case .Vector4, .Color:
            forwardTyped(selectedInputPort, to: outputPort, as: simd_float4.self)
        default:
            // Virtual / unknown: fall back to boxed path
            let value = selectedInputPort.boxedValue()
            outputPort.setBoxedValue(value)
            for connection in outputPort.connections where connection.kind == .Inlet {
                connection.setBoxedValue(value)
            }
        }
    }

    /// Forward a value directly between typed ports, avoiding PortValue boxing.
    private func forwardTyped<T: PortValueRepresentable>(
        _ input: Port, to output: Port, as type: T.Type
    ) {
        guard let typedInput = input as? NodePort<T>,
              let typedOutput = output as? NodePort<T> else {
            // Type mismatch — fall back to boxed path
            let value = input.boxedValue()
            output.setBoxedValue(value)
            for connection in output.connections where connection.kind == .Inlet {
                connection.setBoxedValue(value)
            }
            return
        }

        let value = typedInput.value
        typedOutput.value = value
        typedOutput.valueDidChange = true
        typedOutput.node?.markDirty()
        for connection in typedOutput.connections where connection.kind == .Inlet {
            if let typedConnection = connection as? NodePort<T> {
                typedConnection.value = value
                typedConnection.valueDidChange = true
                typedConnection.node?.markDirty()
            }
        }
    }
}
