//
//  ParameterPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Combine
import Foundation
import Satin

// A Port that wraps a parameter - use for input ports you want to have as a UI
public class ParameterPort<ParamValue : PortValueRepresentable & Codable & Hashable> : NodePort<ParamValue>
{
    private var subscription:AnyCancellable? = nil
    private var _parameter: GenericParameter<ParamValue>

    // Proxy the parameter's description
    // Setter ignores empty values to preserve parameter's description during decoding of old files
    override public var portDescription: String {
        get { _parameter.description }
        set {
            if !newValue.isEmpty {
                _parameter.description = newValue
            }
        }
    }

    // Color and Vector4 share the same Swift type (simd_float4), so the port
    // type derived from the generic parameter is always .Vector4. Colorpicker is
    // the only control type that implies a different PortType than the Swift type
    // would give — all other control types (slider, dropdown, etc.) are purely UI
    // presentation choices within their type. Ideally ports would declare .Color
    // explicitly and the picker would be derived from that, but until Color has its
    // own value type this is the pragmatic bridge.
    @ObservationIgnored override public var portType: PortType {
        if _parameter.controlType == .colorpicker || _parameter.controlType == .colorpalette {
            return .Color
        }
        return super.portType
    }

    override public var parameter: (any Parameter)?
    {
        get { return _parameter }
        set {
            if let newParam = newValue as? GenericParameter<ParamValue>
            {
                self.subscription?.cancel()
                self.subscription = nil
                newParam.value = self._parameter.value
                self._parameter = newParam
                self.value = self._parameter.value

                self.subscription = _parameter.valuePublisher.eraseToAnyPublisher().sink{ [weak self] value in
                        self?.value = value
                }
            }
        }
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
            guard self.valueDidChange else { return }

            if let value,
               self._parameter.value != value
            {
                self._parameter.value = value
            }
        }
    }
}
