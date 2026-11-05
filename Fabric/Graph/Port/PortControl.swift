//
//  PortControl.swift
//  Fabric
//

import Foundation
import Satin

/// The control a parameter inlet offers in the inspector. An inlet whose
/// declaration has a control is a parameter inlet: it rests at a value of its
/// own when unwired, and the document saves that value. Range, options and
/// file types stay on the port's parameter for now.
public enum PortControl: Equatable, Sendable
{
    case slider
    case multiSlider
    case rangeSlider
    case xyPad
    case toggle
    case button
    case inputField
    case stepper
    case colorPicker
    case colorPalette
    case dropdown
    case label
    case filePicker
    /// A parameter with no control of its own, as a Transform's.
    case hidden

    public init(_ controlType: ControlType)
    {
        switch controlType
        {
        case .none: self = .hidden
        case .slider: self = .slider
        case .multislider: self = .multiSlider
        case .rangeslider: self = .rangeSlider
        case .xypad: self = .xyPad
        case .toggle: self = .toggle
        case .button: self = .button
        case .inputfield: self = .inputField
        case .stepper: self = .stepper
        case .colorpicker: self = .colorPicker
        case .colorpalette: self = .colorPalette
        case .dropdown: self = .dropdown
        case .label: self = .label
        case .filepicker: self = .filePicker
        }
    }
}

extension PortType
{
    /// The control `makeFreshPort(name:kind:description:id:)` gives a port of
    /// this type and kind; nil for a plain port. Kept beside the factory's
    /// choices in ParameterValueType and makeFreshParameterPort, which it must
    /// agree with.
    func freshPortControl(kind: PortKind) -> PortControl?
    {
        guard kind == .Inlet else { return nil }

        switch self
        {
        case .Color: return .colorPicker
        case .Bool: return .button
        case .Int, .Float, .String, .Vector2, .Vector3, .Vector4: return .inputField
        case .Transform: return .hidden
        default: return nil
        }
    }
}
