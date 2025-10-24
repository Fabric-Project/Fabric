//
//  ParameterPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Combine
import Foundation

// A Port that wraps a parameter - use for input ports you want to have as a UI
public class ParameterPort<ParamValue : FabricPort & Codable & Equatable & Hashable> : NodePort<ParamValue>
{
    private var subscription:AnyCancellable? = nil
    private let _parameter: GenericParameter<ParamValue>
    
    override public var parameter: (any Parameter)?
    {
        get { return _parameter }
    }
    
    public init(parameter: GenericParameter<ParamValue>)
    {
        self._parameter = parameter
        super.init(name: parameter.label, kind: .Inlet, id:parameter.id)

        self.value = self._parameter.value
        
        self.subscription = parameter.valuePublisher.eraseToAnyPublisher().sink{ [weak self] value in
                self?.value = value
        }
    }
    
    enum CodingKeys : String, CodingKey
    {
        case parameter
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // backwards compat for port update
        if let anyparam = try container.decodeIfPresent(AnyParameter.self, forKey: .parameter),
           let param = anyparam.base as? GenericParameter<ParamValue>
        {
            self._parameter = param
        }
        else
        {
            self._parameter = try GenericParameter(from: decoder)
        }
        
        try super.init(from: decoder)

        self.value = self._parameter.value

        self.subscription = _parameter.valuePublisher.eraseToAnyPublisher().sink{ [weak self] value in
                self?.value = value
        }
    }
    
    deinit
    {
        self.subscription?.cancel()
        self.subscription = nil
    }
    
    override public func encode(to encoder: any Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AnyParameter(self._parameter), forKey: .parameter)

        try super.encode(to: encoder)
    }
    
    override public var value: ParamValue?
    {
        didSet
        {
            if let value
            {
                self._parameter.value = value
            }
        }
    }
}
