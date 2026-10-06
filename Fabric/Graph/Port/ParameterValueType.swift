//
//  ParameterValueType.swift
//  Fabric
//

import Foundation
import Satin
import simd

/// A value type Satin can carry as a parameter, and so a type whose inlets are
/// parameter ports.
///
/// A parameter port holds a value of its own when unwired, saves and loads it
/// through its parameter, and shares that parameter with whatever else reads
/// it, a shader uniform included. Whether the inspector has a control for the
/// type is the inspector's concern (see ParameterGroupView): Transform has
/// none and conforms all the same. Quaternion does not conform: Satin has no
/// quaternion parameter type, so a GenericParameter<simd_quatf> encodes as
/// .generic, which Satin's decoder traps on; a document holding one would
/// crash on open (ParameterPort.init(from:) throws first, so the port comes
/// back plain instead).
///
/// Color is the exception, decided in `PortType.makeFreshParameterPort`.
public protocol ParameterValueType: PortValueRepresentable {
    static func makeDefaultParameterPort(name: String, description: String) -> Port
}

extension Bool: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: BoolParameter(name, false, .button, description))
    }
}

extension Int: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: IntParameter(name, 0, .inputfield, description))
    }
}

extension Float: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield, description))
    }
}

extension String: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: StringParameter(name, "", .inputfield, description))
    }
}

extension simd_float2: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float2Parameter(name, .zero, .inputfield, description))
    }
}

extension simd_float3: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float3Parameter(name, .zero, .inputfield, description))
    }
}

extension simd_float4: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float4Parameter(name, .zero, .inputfield, description))
    }
}

extension simd_float4x4: ParameterValueType {
    public static func makeDefaultParameterPort(name: String, description: String) -> Port {
        ParameterPort(parameter: Float4x4Parameter(name, matrix_identity_float4x4, .inputfield, description))
    }
}
