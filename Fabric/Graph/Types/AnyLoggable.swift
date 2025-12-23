//
//  AnyLoggable.swift
//  Fabric
//
//  Created by Anton Marini on 12/22/25.
//

import Foundation

public class AnyLoggable: Equatable, CustomStringConvertible
{
    public let description: String
    public let debugDescription:String
    
    private var storage: Any
    private let _isEqual: (AnyLoggable) -> Bool

    public init<T: Equatable & CustomDebugStringConvertible>(_ value: T)
    {
            self.debugDescription = String(reflecting: value)

            if let value = value as? CustomStringConvertible
            {
                let typeString = String(describing: type(of: value))
                let description = String(describing: value)
                
                self.description = description.replacing(typeString, with: "")
                    .replacing("(", with: "")
                    .replacing(")", with: "")
            }
            else
            {
                self.description = String(describing: value.self)
            }
       


        self.storage = value
        
        self._isEqual = { other in
            guard let rhs = other.storage as? T else { return false } // different types → not equal
            return value == rhs
        }
    }

    public static func == (lhs: AnyLoggable, rhs: AnyLoggable) -> Bool
    {
        lhs._isEqual(rhs)
    }

    // Optional: a typed accessor
    public func asType<T>(_ type: T.Type) -> T? { storage as? T }
    public func setAsType<T>(_ type: T.Type, value: T) {
        storage = value
    }
}
