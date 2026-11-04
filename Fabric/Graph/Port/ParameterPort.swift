//
//  ParameterPort.swift
//  Fabric
//
//  Created by Anton Marini on 10/19/25.
//

import Foundation
import Satin

/// An inlet with a control: it rests at a value of its own when unwired, and
/// a document saves that value. The port's value is canonical. Its parameter
/// mirrors it, one way, written through the parameter's setter whenever the
/// value changes: for a control to draw its range and options from, and, for
/// a material-backed port, as the uniform the material uploads. Nothing reads
/// the parameter to learn the port's value.
public class ParameterPort<ParamValue : PortValueRepresentable & Codable & Hashable> : NodePort<ParamValue>
{
    private var _parameter: GenericParameter<ParamValue>

    /// The value the inlet holds when nothing gives it one: its last value.
    private var restingValue: ParamValue

    override internal func restoreValue(from boxed: PortValue?)
    {
        // A parameter-backed port has no valueless state. Resolve its resting
        // value before assigning so restoration reports one final value change.
        super.restoreValue(from: boxed ?? restingValue.toPortValue())
    }

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
    override public var portType: PortType {
        if _parameter.controlType == .colorpicker || _parameter.controlType == .colorpalette {
            return .Color
        }
        return super.portType
    }

    /// Setting another parameter, a material's after a shader reload, has it
    /// mirror this port's value from then on.
    override public var parameter: (any Parameter)?
    {
        get { return _parameter }
        set {
            if let newParam = newValue as? GenericParameter<ParamValue>
            {
                newParam.value = self.value ?? self.restingValue
                self._parameter = newParam
            }
        }
    }

    /// The port starts at its parameter's value, the declaration's default.
    public init(parameter: GenericParameter<ParamValue>, id: UUID = UUID())
    {
        self._parameter = parameter
        self.restingValue = parameter.value
        super.init(name: parameter.label, kind: .Inlet, id: id)

        self.value = parameter.value
    }

    /// A file picker's absolute reference inside the document's folder becomes
    /// relative to it, as NodeFileLoadingProtocol.normalizeFileReference has a
    /// picked file. A value put on the port from a document or a carried state
    /// takes the declared range again, but only for a control that enforces its range in
    /// the UI: a slider can only ever have produced in-range values, so an
    /// out-of-range one means the declared range changed since. Input fields
    /// and wired inlets legitimately hold values outside min/max (many
    /// parameters carry FloatParameter's default 0...1 as a placeholder), so
    /// those are left alone.
    override internal func correctAppliedValue(fileReferenceBase: URL?)
    {
        if self._parameter.controlType == .filepicker,
           self.connectedOutlets.isEmpty,
           let fileReferenceBase,
           let reference = self.value as? String, reference.hasPrefix("file://"),
           let url = URL(fileReference: reference, relativeTo: fileReferenceBase),
           let relative = url.fileReference(relativeTo: fileReferenceBase) as? ParamValue,
           relative != self.value
        {
            self.value = relative
        }

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

    override internal func valueDidSet()
    {
        // Disconnecting an upstream port force-sends nil downstream so the
        // inlet doesn't keep stale data; a parameter inlet has no valueless
        // state, so it goes back to resting at its last value. The re-entrant
        // assignment runs this hook again.
        guard let value = self.value
        else
        {
            self.value = self.restingValue
            return
        }

        self.restingValue = value
        // Change flags, node invalidation and callbacks belong to NodePort.value.
        if self._parameter.value != value
        {
            self._parameter.value = value
        }

        super.valueDidSet()
    }
}
