//
//  MathOperator.swift
//  Fabric
//
//  Created by Anton Marini on 5/18/25.
//

import Foundation

enum UnaryMathOperator: CaseIterable, CustomStringConvertible
{
    case sine
    case cosine
    case tangent
    case arcsine
    case arccosine
    case arctangent
    case log
    case log10
    case exp
    case abs
  
    var description: String
    {
        switch self
        {
        case .sine: return "Sin"
        case .cosine: return "Cos"
        case .tangent: return "Tan"
        case .arcsine: return "Asin"
        case .arccosine: return "Acos"
        case .arctangent: return "Atan"
        case .log: return "Log (Natural)"
        case .log10: return "Log10"
        case .exp: return "Exp"
        case .abs: return "Abs"
        }
    }
    
    func perform(lhs: Float) -> Float
    {
        switch self
        {
        case .sine: return sin(lhs)
        case .cosine: return cos(lhs)
        case .tangent: return tan(lhs)
        case .arcsine: return asin(lhs)
        case .arccosine: return acos(lhs)
        case .arctangent: return atan(lhs)
        case .log: return lhs > 0 ? logf(lhs) : 0
        case .log10: return lhs > 0 ? log10f(lhs) : 0
        case .exp: return expf(lhs)
        case .abs: return fabsf(lhs)
        }
    }
}

enum BinaryMathOperator: String, CaseIterable
{
    case Add
    case Subtract
    case Multiply
    case Divide
    case Power
    case Minimum
    case Maximum
    case Modulo
    

    
    func perform(lhs: Float, rhs: Float) -> Float
    {
        switch self
        {
        case .Add: return lhs + rhs
        case .Subtract: return lhs - rhs
        case .Multiply: return lhs * rhs
        case .Divide: return rhs != 0 ? lhs / rhs : 0
        case .Power: return pow(lhs, rhs)
        case .Minimum: return min(lhs, rhs)
        case .Maximum: return max(lhs, rhs)
        case .Modulo: return fmod(lhs, rhs)
        }
    }
}
