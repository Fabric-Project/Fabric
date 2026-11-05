//
//  ParameterGroupView.swift
//  v

//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin
import UniformTypeIdentifiers

/// The controls for the parameter inlets among `ports`, in port order. Each
/// control edits its port; the port's parameter supplies the range, options
/// and kind of control.
struct ParameterGroupView : View
{
    let ports: [Port]
    var fileContentTypes: [UTType] = [.data]

    var body: some View
    {
        VStack(alignment: .leading, spacing:15.0)
        {
            Spacer()
            
            ForEach(self.ports.filter(Self.hasEditor), id: \.id) { port in
                
                Self.editor(for: port, fileContentTypes: self.fileContentTypes)
            }
            
            Spacer(minLength: 0)
        }
    }

    /// Whether the view has a control for the port. One it has none for is
    /// left out rather than shown as a bare label: a Transform's inlet is fed
    /// from the graph, and an unannotated uniform's name is on its inlet.
    static func hasEditor(_ port: Port) -> Bool
    {
        Self.editor(for: port) != nil
    }

    /// The control for the port, or nil where the view has none for its
    /// parameter's control type and value type, or it has no parameter.
    private static func editor(for port: Port, fileContentTypes: [UTType] = [.data]) -> AnyView?
    {
        guard let param = port.parameter else { return nil }
        let view: (any View)?

        switch param.controlType
        {
        case .xypad:
            view = buildXYPad(param: param, port: port)

        case .slider:
            view = buildSlider(param: param, port: port)

        case .multislider:
            switch param.type
            {
            case .float2, .int2: view = build2Slider(param: param, port: port)
            case .float3, .int3: view = build3Slider(param: param, port: port)
            case .float4, .int4: view = build4Slider(param: param, port: port)
            default:             view = nil
            }

        case .dropdown:
            view = buildDropDown(param: param, port: port)

        case .filepicker:
            view = buildFilePicker(param: param, port: port, fileContentTypes: fileContentTypes)

        case .colorpicker:
            view = buildColorPicker(param: param, port: port)

        case .inputfield:
            view = buildInputField(param: param, port: port)

        case .toggle, .button:
            view = buildToggleButton(param: param, port: port)

        // A shader uniform with no annotation.
        case .none:
            view = buildSlider(param: param, port: port)

        default:
            view = nil
        }

        return view.map { AnyView($0) }
    }

    private static func buildToggleButton(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        guard let boolParam = param as? BoolParameter else { return nil }

        return EquatableView<ButtonParameterView>( content: ButtonParameterView(param: boolParam, port: port as? NodePort<Bool>) )
    }
    
    private static func buildSlider(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        if let floatParam = param as? FloatParameter
        {
            return EquatableView<FloatSlider>( content: FloatSlider(param: floatParam, port: port as? NodePort<Float>) )
        }
        
        if let intParam = param as? IntParameter
        {
            return EquatableView<IntSlider>( content: IntSlider(param: intParam, port: port as? NodePort<Int>) )
        }
        
        return nil
    }
    
    private static func build2Slider(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        if let floatParam = param as? Float2Parameter
        {
            return EquatableView<Float2Slider>( content: Float2Slider(param: floatParam, port: port as? NodePort<simd_float2>) )
        }

        if let intParam = param as? Int2Parameter
        {
            return EquatableView<Int2Slider>( content: Int2Slider(param:intParam) )
        }

        return nil
    }
    
    private static func build3Slider(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        if let floatParam = param as? Float3Parameter
        {
            return EquatableView<Float3Slider>( content: Float3Slider(param: floatParam, port: port as? NodePort<simd_float3>) )
        }
        
        if let intParam = param as? Int3Parameter
        {
            return EquatableView<Int3Slider>( content: Int3Slider(param:intParam) )
        }
        
        return nil
    }
    
    private static func build4Slider(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        if let floatParam = param as? Float4Parameter
        {
            return EquatableView<Float4Slider>( content: Float4Slider(param: floatParam, port: port as? NodePort<simd_float4>) )
        }
        
        if let intParam = param as? Int4Parameter
        {
            return EquatableView<Int4Slider>( content: Int4Slider(param:intParam) )
        }
        
        return nil
    }
    
    private static func buildXYPad(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        guard let float2Param = param as? Float2Parameter else { return nil }

        return EquatableView<XYPad>(content: XYPad(param: float2Param, port: port as? NodePort<simd_float2>) )
    }
    
    private static func buildDropDown(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        guard let stringParam = param as? StringParameter else { return nil }
        
        return StringMenu(parameter: stringParam, port: port as? NodePort<String>)
            .frame(height:20)
    }
    
    private static func buildColorPicker(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        if let float4Param = param as? Float4Parameter
        {
            return Color4ParameterView(parameter: float4Param, port: port as? NodePort<simd_float4>).frame(height:20)
        }
        
        if let float3Param = param as? Float3Parameter
        {
            return Color3ParameterView(parameter: float3Param, port: port as? NodePort<simd_float3>).frame(height:20)
        }
        
        return nil
    }
    
    private static func buildInputField(param: any Satin.Parameter, port: Port) -> (any View)?
    {
        if let stringParam = param as? StringParameter {
            return InputFieldView(param: stringParam, port: port as? NodePort<String>)
        }
        
        if let floatParam = param as? GenericParameter<Float> {
            return FloatInputFieldView(param: floatParam, port: port as? NodePort<Float>)
        }
        
        if let floatParam = param as? GenericParameter<simd_float2> {
            return Float2InputFieldView(param: floatParam, port: port as? NodePort<simd_float2>)
        }

        if let floatParam = param as? GenericParameter<simd_float3> {
            return Float3InputFieldView(param: floatParam, port: port as? NodePort<simd_float3>)
        }

        if let floatParam = param as? GenericParameter<simd_float4> {
            return Float4InputFieldView(param: floatParam, port: port as? NodePort<simd_float4>)
        }
        
        if let intParam = param as? GenericParameter<Int> {
            return IntInputFieldView(param: intParam, port: port as? NodePort<Int>)
        }
        
        if let intParam = param as? GenericParameter<simd_int2> {
            return Int2InputFieldView(param: intParam)
        }

        if let intParam = param as? GenericParameter<simd_int3> {
            return Int3InputFieldView(param: intParam)
        }

        if let intParam = param as? GenericParameter<simd_int4> {
            return Int4InputFieldView(param: intParam)
        }

        return nil
    }
    
    private static func buildFilePicker(param: any Satin.Parameter, port: Port, fileContentTypes: [UTType]) -> (any View)?
    {
        guard let stringParam = param as? StringParameter else { return nil }

        return FileImportParameterView(parameter: stringParam, port: port as? NodePort<String>, allowedContentTypes: fileContentTypes)
            .equatable()
    }
}
