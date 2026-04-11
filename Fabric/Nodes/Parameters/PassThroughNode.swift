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
}
