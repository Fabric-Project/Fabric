//
//  ParameterGroupView.swift
//  v

//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin
import UniformTypeIdentifiers

struct ParameterGroupView : View
{
    let parameterGroup:ParameterGroup
    var fileContentTypes: [UTType] = [.data]
    /// The graph the parameters' nodes are in, handed to each control so an
    /// edit made through it is recorded there with the document's others.
    var graph: Graph? = nil

    var body: some View
    {
        VStack(alignment: .leading, spacing:15.0)
        {
            Spacer()
            
            ForEach(Self.entries(of: self.parameterGroup), id: \.identity) { entry in

                Self.editor(for: entry.param, fileContentTypes: self.fileContentTypes, graph: self.graph)
            }
            
            Spacer(minLength: 0)
        }
    }

    /// A control's place in the view, keyed by the parameter object, not
    /// its id: clone set members' inner parameters share ids, and a graph
    /// shows a parameter from each member it publishes ports of.
    struct Entry
    {
        let param: any Parameter
        var identity: ObjectIdentifier { ObjectIdentifier(param) }
    }

    /// The group's parameters the view has a control for.
    static func entries(of group: ParameterGroup) -> [Entry]
    {
        group.params.filter(Self.hasEditor).map(Entry.init)
    }

    /// Whether the view has a control for the parameter. One it has none for
    /// is left out rather than shown as a bare label: a Transform's inlet is
    /// fed from the graph, and an unannotated uniform's name is on its inlet.
    static func hasEditor(_ param: any Parameter) -> Bool
    {
        Self.editor(for: param) != nil
    }

    /// The control for the parameter, or nil where the view has none for its
    /// control type and value type.
    private static func editor(for param: any Parameter, fileContentTypes: [UTType] = [.data],
                               graph: Graph? = nil) -> AnyView?
    {
        let view: (any View)?

        switch param.controlType
        {
        case .xypad:
            view = buildXYPad(param: param, graph: graph)

        case .slider:
            view = buildSlider(param: param, graph: graph)

        case .multislider:
            switch param.type
            {
            case .float2, .int2: view = build2Slider(param: param, graph: graph)
            case .float3, .int3: view = build3Slider(param: param, graph: graph)
            case .float4, .int4: view = build4Slider(param: param, graph: graph)
            default:             view = nil
            }

        case .dropdown:
            view = buildDropDown(param: param, graph: graph)

        case .filepicker:
            view = buildFilePicker(param: param, fileContentTypes: fileContentTypes, graph: graph)

        case .colorpicker:
            view = buildColorPicker(param: param, graph: graph)

        case .inputfield:
            view = buildInputField(param: param, graph: graph)

        case .toggle, .button:
            view = buildToggleButton(param: param, graph: graph)

        // A shader uniform with no annotation.
        case .none:
            view = buildSlider(param: param, graph: graph)

        default:
            view = nil
        }

        return view.map { AnyView($0) }
    }

    private static func buildToggleButton(param: any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        guard let boolParam = param as? BoolParameter else { return nil }

        return EquatableView<ButtonParameterView>( content: ButtonParameterView(param:boolParam, graph: graph) )
    }
    
    private static func buildSlider(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        if let floatParam = param as? FloatParameter
        {
            return EquatableView<FloatSlider>( content: FloatSlider(param:floatParam, graph: graph) )
        }
        
        if let intParam = param as? IntParameter
        {
            return EquatableView<IntSlider>( content: IntSlider(param:intParam, graph: graph) )
        }
        
        return nil
    }
    
    private static func build2Slider(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        if let floatParam = param as? Float2Parameter
        {
            return EquatableView<Float2Slider>( content: Float2Slider(param:floatParam, graph: graph) )
        }

        if let intParam = param as? Int2Parameter
        {
            return EquatableView<Int2Slider>( content: Int2Slider(param:intParam, graph: graph) )
        }

        return nil
    }
    
    private static func build3Slider(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        if let floatParam = param as? Float3Parameter
        {
            return EquatableView<Float3Slider>( content: Float3Slider(param:floatParam, graph: graph) )
        }
        
        if let intParam = param as? Int3Parameter
        {
            return EquatableView<Int3Slider>( content: Int3Slider(param:intParam, graph: graph) )
        }
        
        return nil
    }
    
    private static func build4Slider(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        if let floatParam = param as? Float4Parameter
        {
            return EquatableView<Float4Slider>( content: Float4Slider(param:floatParam, graph: graph) )
        }
        
        if let intParam = param as? Int4Parameter
        {
            return EquatableView<Int4Slider>( content: Int4Slider(param:intParam, graph: graph) )
        }
        
        return nil
    }
    
    private static func buildXYPad(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        guard let float2Param = param as? Float2Parameter else { return nil }

        return EquatableView<XYPad>(content: XYPad(param: float2Param, graph: graph) )
    }
    
    private static func buildDropDown(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        guard let stringParam = param as? StringParameter else { return nil }
        
        return StringMenu(parameter: stringParam, graph: graph)
            .frame(height:20)
    }
    
    private static func buildColorPicker(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        if let float4Param = param as? Float4Parameter
        {
            return Color4ParameterView(parameter: float4Param, graph: graph).frame(height:20)
        }
        
        if let float3Param = param as? Float3Parameter
        {
            return Color3ParameterView(parameter: float3Param, graph: graph).frame(height:20)
        }
        
        return nil
    }
    
    private static func buildInputField(param:any Satin.Parameter, graph: Graph?) -> (any View)?
    {
        if let stringParam = param as? StringParameter {
            return InputFieldView(param: stringParam, graph: graph)
        }
        
        if let floatParam = param as? GenericParameter<Float> {
            return FloatInputFieldView(param: floatParam, graph: graph)
        }
        
        if let floatParam = param as? GenericParameter<simd_float2> {
            return Float2InputFieldView(param: floatParam, graph: graph)
        }

        if let floatParam = param as? GenericParameter<simd_float3> {
            return Float3InputFieldView(param: floatParam, graph: graph)
        }

        if let floatParam = param as? GenericParameter<simd_float4> {
            return Float4InputFieldView(param: floatParam, graph: graph)
        }
        
        if let intParam = param as? GenericParameter<Int> {
            return IntInputFieldView(param: intParam, graph: graph)
        }
        
        if let intParam = param as? GenericParameter<simd_int2> {
            return Int2InputFieldView(param: intParam, graph: graph)
        }

        if let intParam = param as? GenericParameter<simd_int3> {
            return Int3InputFieldView(param: intParam, graph: graph)
        }

        if let intParam = param as? GenericParameter<simd_int4> {
            return Int4InputFieldView(param: intParam, graph: graph)
        }

        return nil
    }
    
    private static func buildFilePicker(param:any Satin.Parameter, fileContentTypes: [UTType], graph: Graph?) -> (any View)?
    {
        guard let stringParam = param as? StringParameter else { return nil }

        return FileImportParameterView(parameter: stringParam, graph: graph, allowedContentTypes: fileContentTypes)
            .equatable()
    }
}
