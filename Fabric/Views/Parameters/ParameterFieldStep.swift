//
//  ParameterFieldStep.swift
//  Fabric
//

import Foundation
import Satin
import simd

/// The drag step for a parameter's numeric field, from its range.
///
/// Satin gives a parameter made without a range the range 0…1, so a float
/// field with no stated range steps by hundredths; a node that wants otherwise
/// states a range. A vector steps each component by that component's range.
public enum ParameterFieldStep
{
    public static func step<V: BinaryFloatingPoint>(for param: GenericParameter<V>, fractionDigits: Int) -> V
    {
        let ranged = param as? GenericParameterWithMinMax<V>
        return V(NumericFieldStepping.step(forRange: Double(ranged?.min ?? 0),
                                           max: Double(ranged?.max ?? 0),
                                           integral: false,
                                           fractionDigits: fractionDigits))
    }

    public static func step<V: FixedWidthInteger>(for param: GenericParameter<V>) -> V
    {
        let ranged = param as? GenericParameterWithMinMax<V>
        return V(NumericFieldStepping.step(forRange: Double(ranged?.min ?? 0),
                                           max: Double(ranged?.max ?? 0),
                                           integral: true,
                                           fractionDigits: 0))
    }

    public static func steps<V: SIMD>(for param: GenericParameter<V>, fractionDigits: Int) -> [V.Scalar]
        where V.Scalar: BinaryFloatingPoint
    {
        let ranged = param as? GenericParameterWithMinMax<V>
        return param.value.indices.map { i in
            V.Scalar(NumericFieldStepping.step(forRange: Double(ranged?.min[i] ?? 0),
                                               max: Double(ranged?.max[i] ?? 0),
                                               integral: false,
                                               fractionDigits: fractionDigits))
        }
    }

    public static func steps<V: SIMD>(for param: GenericParameter<V>) -> [V.Scalar]
        where V.Scalar: FixedWidthInteger
    {
        let ranged = param as? GenericParameterWithMinMax<V>
        return param.value.indices.map { i in
            V.Scalar(NumericFieldStepping.step(forRange: Double(ranged?.min[i] ?? 0),
                                               max: Double(ranged?.max[i] ?? 0),
                                               integral: true,
                                               fractionDigits: 0))
        }
    }
}
