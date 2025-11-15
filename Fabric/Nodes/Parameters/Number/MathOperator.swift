//
//  MathOperator.swift
//  Fabric
//
//  Created by Anton Marini on 5/18/25.
//

import Foundation

enum UnaryMathOperator: String, CaseIterable
{
    case Sine
    case Cosine
    case Tangent
    case Arcsine
    case Arccosine
    case Arctangent
    case Log
    case Log10
    case Exp
    case Abs
    
    func perform(_ lhs: Float) -> Float
    {
        switch self
        {
        case .Sine: return sin(lhs)
        case .Cosine: return cos(lhs)
        case .Tangent: return tan(lhs)
        case .Arcsine: return asin(lhs)
        case .Arccosine: return acos(lhs)
        case .Arctangent: return atan(lhs)
        case .Log: return lhs > 0 ? logf(lhs) : 0
        case .Log10: return lhs > 0 ? log10f(lhs) : 0
        case .Exp: return expf(lhs)
        case .Abs: return fabsf(lhs)
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
        case .Modulo: return rhs != 0 ? fmod(lhs, rhs) : 0
        }
    }
}
