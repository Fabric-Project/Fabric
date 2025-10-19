//
//  ParameterPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation

public class ParameterPort<ParamValue : Codable & Equatable & Hashable> : NodePort<ParamValue>
{
    public let parameter: GenericParameter<ParamValue>
    
    public init(parameter: GenericParameter<ParamValue>)
    {
        self.parameter = parameter
        
        super.init(name: parameter.label, kind: .Inlet, id:parameter.id)
    }
    
    required public init(from decoder: any Decoder) throws {
        self.parameter = try GenericParameter(from: decoder)

        try super.init(from: decoder)
    }
    
    override public func encode(to encoder: any Encoder) throws {
        
        try super.encode(to: encoder)
        
        try self.parameter.encode(to: encoder)
    }
    
    override public var valueDidChange: Bool
    {
        didSet
        {
            self.parameter.valueDidChange = self.valueDidChange
        }
    }
    
    override public var value: ParamValue?
    {
        get
        {
            self.parameter.value
        }
        set
        {
            if let newValue = newValue
            {
                if  parameter.value != newValue
                {
                    parameter.value = newValue
                    self.valueDidChange = true
                    self.node?.markDirty()
                }
            }
        }
    }
}
