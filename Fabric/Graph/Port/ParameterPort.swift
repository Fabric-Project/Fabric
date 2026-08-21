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
                // A replacement parameter arrives with an id of its own; re-key
                // it to keep the invariant hydrate(from:) describes.
                newParam.id = self.id
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
    
    /// After adopting the document's value, re-impose the declared range — but
    /// only for controls that enforce their range in the UI (a slider can only
    /// ever have produced in-range values, so out-of-range persisted state
    /// means the declared range changed since the save). Input fields and
    /// connected inlets legitimately hold values outside min/max — many
    /// parameters carry FloatParameter's default 0...1 range as a placeholder —
    /// so those are left untouched.
    override internal func hydrate(from decoded: Port)
    {
        super.hydrate(from: decoded)

        self._parameter.id = self.id

        guard self._parameter.controlType == .slider,
              let value = self.value,
              let ranged = self._parameter as? GenericParameterWithMinMax<ParamValue>
        else { return }

        if let clamped = Self.clampedComparable(value, min: ranged.min, max: ranged.max),
           clamped != value
        {
            self.value = clamped
        }
    }

    private static func clampedComparable(_ value: ParamValue, min minValue: ParamValue, max maxValue: ParamValue) -> ParamValue?
    {
        func clamp<C: Comparable>(_ candidate: C, _ lower: C, _ upper: C) -> C
        {
            guard lower <= upper else { return candidate }
            return Swift.min(Swift.max(candidate, lower), upper)
        }

        if let candidate = value as? Float, let lower = minValue as? Float, let upper = maxValue as? Float
        {
            return clamp(candidate, lower, upper) as? ParamValue
        }

        if let candidate = value as? Int, let lower = minValue as? Int, let upper = maxValue as? Int
        {
            return clamp(candidate, lower, upper) as? ParamValue
        }

        return nil
    }

    override public var value: ParamValue?
    {
        didSet
        {
            // A parameter-backed inlet has no valueless state: the parameter is
            // its resting value. Disconnecting an upstream port force-sends nil
            // downstream so the inlet doesn't keep stale data, which would
            // otherwise leave this port — and everything reading it — with a
            // missing value for as long as it stays unwired. Re-seat on the
            // parameter instead; the re-entrant assignment runs the change
            // bookkeeping below.
            guard let value = self.value
            else
            {
                self.value = self._parameter.value
                return
            }

            // Overriding the property's didSet replaces the parent's
            // observer, so the change-tracking bookkeeping the parent
            // does (NodePort.value) has to be repeated here. Without it,
            // values pushed in via the parameter's Combine publisher
            // (the path UI dropdowns / inputfields go through) update
            // the value but never raise `valueDidChange`, so executors
            // that gate on `valueDidChange` — e.g. NumberBinaryOperator
            // re-parsing its operator string — silently miss the change
            // and stay on the previous value.
            self.valueDidChange = true
            self.node?.markDirty()
            self.onValueChanged?()

            if self._parameter.value != value
            {
                self._parameter.value = value
            }
        }
    }
}
