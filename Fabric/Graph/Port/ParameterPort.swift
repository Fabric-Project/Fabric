//
//  ParameterPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation

// A Port that wraps a parameter - use for input ports you want to have as a UI
public class ParameterPort<ParamValue : FabricPort & Codable & Equatable & Hashable> : NodePort<ParamValue>
{
    public let parameter: GenericParameter<ParamValue>
    
    public init(parameter: GenericParameter<ParamValue>)
    {
        self.parameter = parameter
        
        super.init(name: parameter.label, kind: .Inlet, id:parameter.id)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case parameter
    }
    
    required public init(from decoder: any Decoder) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // backwards compat for port update
        if let anyparam = try container.decodeIfPresent(AnyParameter.self, forKey: .parameter),
           let param = anyparam.base as? GenericParameter<ParamValue>
        {
            self.parameter = param
        }
        else
        {
            self.parameter = try GenericParameter(from: decoder)
        }

        try super.init(from: decoder)
    }
    
    override public func encode(to encoder: any Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AnyParameter(self.parameter), forKey: .parameter)

        try super.encode(to: encoder)
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
