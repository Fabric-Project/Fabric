//
//  NumericNodeSupport.swift
//  Fabric
//

import Satin

let singleNumericTypes: [PortType] = [.Float, .Int, .Vector2, .Vector3, .Vector4, .Color, .Quaternion, .Transform]
let interpolatableSingleTypes: [PortType] = [.Float, .Vector2, .Vector3, .Vector4, .Color, .Quaternion, .Transform]
let interpolatableArrayTypes: [PortType] = interpolatableSingleTypes.map { .Array(portType: $0) }

func metricParameter(_ description: String) -> ParameterPort<String>
{
    ParameterPort(parameter: StringParameter(
        "Distance Metric",
        NumericDistanceMetric.euclidean.rawValue,
        NumericDistanceMetric.allCases.map(\.rawValue),
        .dropdown,
        description
    ))
}

func currentMetric(from port: ParameterPort<String>) -> NumericDistanceMetric
{
    guard let value = port.value else { return .euclidean }
    return NumericDistanceMetric(rawValue: value) ?? .euclidean
}
