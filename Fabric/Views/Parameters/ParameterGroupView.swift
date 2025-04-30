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
        VStack(spacing:3.0)
        {
            Spacer()
            
            ForEach(self.parameterGroup.params.indices, id: \.self) { index in
                    
                self.parameterViewFromParameter(self.parameterGroup.params[index])

                }
            
            Spacer(minLength: 0)

        }
    }
    
    func parameterViewFromParameter(_ param:any Parameter) -> AnyView
    {
        switch param.controlType
        {
            // We get this from our metal shaders uniforms
        case .none:
            switch param.type
            {
            case .double, .float:
                return  AnyView(self.buildSlider(param: param))
            default:
                return AnyView(self.buildLabel(param: param))
                
            
            }
            
        case .xypad:
            return AnyView(self.buildXYPad(param: param))
            
        case .slider:
            return AnyView(self.buildSlider(param: param))
            
        case .dropdown:
            return AnyView(self.buildDropDown(param: param))
            
        case .filepicker:
            return AnyView(self.buildFilePicker(param: param))
            
        case .colorpicker:
            return AnyView(self.buildColorPicler(param: param))

        case .inputfield:
            return AnyView(self.buildInputField(param: param))

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
    
    private func buildSlider(param:any Satin.Parameter) -> any View
    {
             
//        if let doubleParam = param as? DoubleParameter
//        {
////            let valueBinding = Binding( get: { doubleParam.value },
////                                        set: { newValue in
////                doubleParam.value = newValue
////            })
//
//            return  DragableWrapperView<EquatableView<FloatSlider>>(bindingManager:self.bindingManager,
//                                                                    content: {  FloatSlider(param:doubleParam,
//                                                                                            clock: self.clock,
//                                                                                            metaParameterState: self.metaParameterState)
//                                                                    .equatable()
//            } )
//        }
        if let floatParam = param as? FloatParameter
        {
    
            return EquatableView<FloatSlider>( content: FloatSlider(param:floatParam) )
                .frame(height:20)

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

        let valueBinding = Binding( get: { stringParam.value },
                                    set: { newValue in
            stringParam.value = newValue
        })
        
        return StringMenu(value: valueBinding, options: stringParam.options, valueName: stringParam.label)
            .frame(height:20)
    }
    
    private func buildColorPicler(param:any Satin.Parameter) -> any View
    {
        guard let float4Param = param as? Float4Parameter else { return Text(param.label) }

        
        return ColorParameterView(parameter: float4Param).frame(height:20)
    }
    
    private func buildInputField(param:any Satin.Parameter) -> any View
    {
        guard let stringParam = param as? StringParameter else { return Text(param.label) }
        
        return InputFieldView(param: stringParam)
                .frame(height:20)
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


        return FileGridView(stringParameter: stringParam )
            .equatable()
    }
}
