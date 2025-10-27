//
//  LogicOperator.swift
//  Fabric
//
//  Created by Anton Marini on 10/26/25.
//

import Foundation

enum LogicOperator: String, CaseIterable
{
    case Equals
    case NotEquals
    case And
    case Or
    
    func perform(lhs:Bool, rhs:Bool) -> Bool
    {
        switch self
        {
        case .Equals:
            return lhs == rhs
        case .And:
            return lhs && rhs
        case .Or:
            return lhs || rhs
        case .NotEquals:
            return lhs != rhs
        }
    }
    
}
