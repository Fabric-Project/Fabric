//
//  PassThroughNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import simd
import Metal
import SwiftUI

/// Types that can provide a default `ParameterPort` for editable UI in the node graph.
public protocol DefaultParameterProviding: PortValueRepresentable {
    static func makeDefaultParameterPort(name: String, description: String) -> Port
}

extension Bool: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: BoolParameter(name, false, .button, description))
    }
}

extension Int: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: IntParameter(name, 0, .inputfield, description))
    }
}

extension Float: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield, description))
    }
}

extension String: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: StringParameter(name, "", .inputfield, description))
    }
}

extension simd_float2: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float2Parameter(name, .zero, .inputfield, description))
    }
}

extension simd_float3: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float3Parameter(name, .zero, .inputfield, description))
    }
}

extension simd_float4: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float4Parameter(name, .zero, .inputfield, description))
    }
}

extension simd_float4x4: DefaultParameterProviding {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float4x4Parameter(name, matrix_identity_float4x4, .inputfield, description))
    }
}

/// Patching utility node that passes a value through without modification.
/// Uses an editable parameter port for the input when the type supports it.
public class PassThroughNode<T: PortValueRepresentable>: Node
{
    override public class var name: String { T.portType.rawValue }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for \(T.portType.rawValue)." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let inputPort: Port
        if let editable = T.self as? any DefaultParameterProviding.Type {
            inputPort = editable.makeDefaultParameterPort(
                name: T.portType.rawValue,
                description: "Input \(T.portType.rawValue)"
            )
        } else {
            inputPort = NodePort<T>(name: T.portType.rawValue, kind: .Inlet, description: "Input \(T.portType.rawValue)")
        }

        return ports +
        [
            ("input", inputPort),
            ("output", NodePort<T>(name: T.portType.rawValue, kind: .Outlet, description: "Output \(T.portType.rawValue)")),
        ]
    }

    // Port Proxy
    public var input: NodePort<T> { port(named: "input") }
    public var output: NodePort<T> { port(named: "output") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.output.send(self.input.value)
    }

    // MARK: - Settings

    /// Settings view is meaningful only for numeric specialisations
    /// whose `ParameterPort` has a min/max range that can be surfaced
    /// as a slider. Other types fall through to the default no-op.
    override public func providesSettingsView() -> Bool {
        T.self == Float.self || T.self == Int.self
    }

    override public func settingsView() -> AnyView {
        if let casted = self as? PassThroughNode<Float> {
            return AnyView(PassThroughFloatSettingsView(node: casted))
        }
        if let casted = self as? PassThroughNode<Int> {
            return AnyView(PassThroughIntSettingsView(node: casted))
        }
        return AnyView(EmptyView())
    }
}

// MARK: - Settings views

/// Editable min / max bounds for a `PassThroughNode<Float>`. Toggling
/// "Slider in inspector" flips the underlying `FloatParameter`'s
/// `controlType` between `.inputfield` and `.slider`, so
/// `ParameterGroupView`'s switch picks the appropriate inspector
/// control on next rebuild.
struct PassThroughFloatSettingsView: View {

    let node: PassThroughNode<Float>

    /// `Parameter` isn't `@Observable`, so SwiftUI can't pick up
    /// `parameter.controlType` mutations through a computed binding —
    /// the Toggle wouldn't visually flip on click. Mirror it as
    /// local `@State` and write through on change. Safe from the
    /// earlier popover-rebuild loop because the inspector refresh is
    /// deferred to `onDisappear` rather than fired inside `onChange`.
    @State private var useSlider: Bool = false
    @State private var minBuffer: String = ""
    @State private var maxBuffer: String = ""

    private var parameter: FloatParameter? { node.input.parameter as? FloatParameter }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set bounds and switch the inspector control to a slider.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Slider in inspector", isOn: $useSlider)
                .onChange(of: useSlider) { _, new in
                    parameter?.controlType = new ? .slider : .inputfield
                }

            HStack {
                Text("Min").frame(width: 30, alignment: .leading)
                TextField("0", text: $minBuffer).onSubmit(commit)
            }
            HStack {
                Text("Max").frame(width: 30, alignment: .leading)
                TextField("1", text: $maxBuffer).onSubmit(commit)
            }
        }
        .onAppear {
            if let p = parameter {
                useSlider = p.controlType == .slider
                minBuffer = String(p.min)
                maxBuffer = String(p.max)
            }
        }
        // Inspector rebuild is deferred until the popover closes —
        // `GraphCanvas` keys `.id(...)` to `shouldUpdateConnections`,
        // so toggling it while the popover is up tears the popover
        // down and re-renders it.
        .onDisappear {
            let graph = node.graph
            DispatchQueue.main.async { graph?.shouldUpdateConnections.toggle() }
        }
    }

    private func commit() {
        guard let p = parameter else { return }
        // `FloatParameter.min`/`max` setters fire publishers that
        // `FloatSlider` subscribes to — no inspector rebuild needed.
        if let v = Float(minBuffer) { p.min = v }
        if let v = Float(maxBuffer) { p.max = v }
    }
}

/// Mirror of `PassThroughFloatSettingsView` for `PassThroughNode<Int>`.
struct PassThroughIntSettingsView: View {

    let node: PassThroughNode<Int>

    @State private var useSlider: Bool = false
    @State private var minBuffer: String = ""
    @State private var maxBuffer: String = ""

    private var parameter: IntParameter? { node.input.parameter as? IntParameter }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set bounds and switch the inspector control to a slider.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Slider in inspector", isOn: $useSlider)
                .onChange(of: useSlider) { _, new in
                    parameter?.controlType = new ? .slider : .inputfield
                }

            HStack {
                Text("Min").frame(width: 30, alignment: .leading)
                TextField("0", text: $minBuffer).onSubmit(commit)
            }
            HStack {
                Text("Max").frame(width: 30, alignment: .leading)
                TextField("1", text: $maxBuffer).onSubmit(commit)
            }
        }
        .onAppear {
            if let p = parameter {
                useSlider = p.controlType == .slider
                minBuffer = String(p.min)
                maxBuffer = String(p.max)
            }
        }
        .onDisappear {
            let graph = node.graph
            DispatchQueue.main.async { graph?.shouldUpdateConnections.toggle() }
        }
    }

    private func commit() {
        guard let p = parameter else { return }
        if let v = Int(minBuffer) { p.min = v }
        if let v = Int(maxBuffer) { p.max = v }
    }
}
