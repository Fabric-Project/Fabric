//
//  ParameterGroupView.swift
//  v

//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin

struct ParameterGroupView : View
{
    let parameterGroup:ParameterGroup

    var body: some View
    {
        VStack(alignment: .leading, spacing:15.0)
        {
            Spacer()
            
            ForEach(self.parameterGroup.params, id:\.id) { param in
                
                self.parameterViewFromParameter(param)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    func parameterViewFromParameter(_ param:any Parameter) -> AnyView
    {
        switch param.controlType
        {
            // We get this from our metal shaders uniforms
            
        case .xypad:
            return AnyView(self.buildXYPad(param: param))
            
        case .slider:
            switch param.type
            {
            case .double, .float:
                return  AnyView(self.buildSlider(param: param))
                
            default:
                return AnyView(self.buildLabel(param: param))
            }

            
        case .multislider:
            switch param.type
            {
            case .float2:
                return  AnyView(self.build2Slider(param: param))

            case .float3:
                return  AnyView(self.build3Slider(param: param))

            case .float4:
                return  AnyView(self.build4Slider(param: param))

            default:
                return AnyView(self.buildLabel(param: param))
            }
            
        case .dropdown:
            return AnyView(self.buildDropDown(param: param))
            
        case .filepicker:
            return AnyView(self.buildFilePicker(param: param))
            
        case .colorpicker:
            return AnyView(self.buildColorPicler(param: param))

        case .inputfield:
            return AnyView(self.buildInputField(param: param))
            
        case .toggle, .button:
            return AnyView(self.buildToggleButton(param:param))
            
            
        case .none:
            switch param.type
            {
            case .double, .float:
                return  AnyView(self.buildSlider(param: param))
                            
            default:
                return AnyView(self.buildLabel(param: param))
            }
            
        default:
            return AnyView(self.buildLabel(param: param))
            
            
//        case .none:
//            return nil
//        case .multislider:
//        case .xypad:
//        case .toggle:
//        case .button:
//        case .inputfield:
            
//        case .colorpalette:
//        case .label:
        }
    }
    
    private func buildLabel(param:any Satin.Parameter) -> any View
    {
        return Text(param.label)
    }
    
    private func buildToggleButton(param: any Satin.Parameter) -> any View
    {
        if let boolParam = param as? BoolParameter
        {
            return EquatableView<ButtonParameterView>( content: ButtonParameterView(param:boolParam) )
        }
        
        return Text(param.label)

    }
    
    private func buildSlider(param:any Satin.Parameter) -> any View
    {
        if let floatParam = param as? FloatParameter
        {
            return EquatableView<FloatSlider>( content: FloatSlider(param:floatParam) )
        }
        
        return Text(param.label)
    }
    
    private func build2Slider(param:any Satin.Parameter) -> any View
    {
        if let floatParam = param as? Float2Parameter
        {
            return EquatableView<Float2Slider>( content: Float2Slider(param:floatParam) )
        }
        
        return Text(param.label)
    }
    
    private func build3Slider(param:any Satin.Parameter) -> any View
    {
        if let floatParam = param as? Float3Parameter
        {
            return EquatableView<Float3Slider>( content: Float3Slider(param:floatParam) )
        }
        
        return Text(param.label)
    }
    
    private func build4Slider(param:any Satin.Parameter) -> any View
    {
        if let floatParam = param as? Float4Parameter
        {
            return EquatableView<Float4Slider>( content: Float4Slider(param:floatParam) )
        }
        
        return Text(param.label)
    }
    
    
    private func buildXYPad(param:any Satin.Parameter) -> any View
    {
                 
        if let float2Param = param as? Float2Parameter
        {
           
            return  EquatableView<XYPad>(content: XYPad(param: float2Param) )
            
        }
        
        return Text(param.label)
    }
    
    private func buildDropDown(param:any Satin.Parameter) -> any View
    {
        guard let stringParam = param as? StringParameter else { return Text(param.label) }
        
        return StringMenu(parameter: stringParam)
            .frame(height:20)
    }
    
    private func buildColorPicler(param:any Satin.Parameter) -> any View
    {
        if let float4Param = param as? Float4Parameter// ?? param as? GenericParameter<simd_float4>
        {
            return Color4ParameterView(parameter: float4Param).frame(height:20)
        }
        
        else if let float3Param = param as? Float3Parameter// ?? param as? GenericParameter<simd_float3>
        {
            return Color3ParameterView(parameter: float3Param).frame(height:20)
        }
        
        else
        {
            return Text(param.label)
        }
    }
    
    private func buildInputField(param:any Satin.Parameter) -> any View
    {
        if let stringParam = param as? StringParameter {
            return InputFieldView(param: stringParam)
        }
        
        else if let floatParam = param as? GenericParameter<Float> {
            return FloatInputFieldView(param: floatParam)
        }
        
        else if let floatParam = param as? GenericParameter<simd_float2> {
            return Float2InputFieldView(param: floatParam)
        }

        else if let floatParam = param as? GenericParameter<simd_float3> {
            return Float3InputFieldView(param: floatParam)
        }

        else if let floatParam = param as? GenericParameter<simd_float4> {
            return Float4InputFieldView(param: floatParam)
        }
        
        else if let intParam = param as? GenericParameter<Int> {
            return IntInputFieldView(param: intParam)
        }
        
        else if let intParam = param as? GenericParameter<simd_int2> {
            return Int2InputFieldView(param: intParam)
        }

        else if let intParam = param as? GenericParameter<simd_int3> {
            return Int3InputFieldView(param: intParam)
        }

        else if let intParam = param as? GenericParameter<simd_int4> {
            return Int4InputFieldView(param: intParam)
        }

        
        else {
            return Text(param.label)
        }
    }
    
    private func buildFilePicker(param:any Satin.Parameter) -> any View
    {
        guard let stringParam = param as? StringParameter else { return Text(param.label) }
                
//        let valueBinding = Binding<URL?>( get: { URL(fileURLWithPath:  stringParam.value ) },
//                                    set: { newValue in
//            stringParam.value = newValue?.standardizedFileURL.absoluteString ?? ""
//        })
//
//        let modelsBinding = Binding<[FileAndThumbnailModel]>( get: {
//            stringParam.options.compactMap( { FileAndThumbnailModel(fileURL: URL(string:$0)!, selected: false) } )
//        },
//                                          set: { newValue in
//            stringParam.options = newValue.compactMap( { $0.fileURL.standardizedFileURL.absoluteString } )
//        })


        return FileImportParameterView(parameter: stringParam )
            .equatable()
    }
}
