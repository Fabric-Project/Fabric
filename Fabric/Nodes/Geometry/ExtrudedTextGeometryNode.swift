//
//  BoxGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/25/25.
//
import Satin
import Foundation
import simd
import Metal
import CoreText

public class ExtrudedTextGeometryNode : BaseGeometryNode
{
    public override class var name:String { "3D Text Geometry" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputText", ParameterPort(parameter:StringParameter("Text", "Testing", .inputfield))),
        ("inputFont", ParameterPort(parameter:StringParameter("Font", "Helvetica", Self.installedFonts(), .dropdown))),

        ] + ports
    }
    
    // Proxy Ports
    public var inputText:ParameterPort<String> { port(named: "inputText")  }
    public var inputFont:ParameterPort<String> { port(named: "inputFont")  }
    
    public override var geometry: ExtrudedTextGeometry { _geometry }

    private let _geometry = ExtrudedTextGeometry(text: "Testing", fontSize: 1.0)

    override public func startExecution(context: GraphExecutionContext) {
        super.startExecution(context: context)

        if let fontParam = self.inputFont.parameter as? StringParameter
        {
            fontParam.options = Self.installedFonts()
        }
    }
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputText.valueDidChange,
           let inputText = self.inputText.value
        {
            self.geometry.text = inputText
            shouldOutputGeometry = true
        }
        
        if self.inputFont.valueDidChange,
           let inputFont = self.inputFont.value
        {
            self.geometry.fontName = inputFont
            shouldOutputGeometry = true
        }
        
//        if self.inputWidthParam.valueDidChange
//        {
//            self.geometry.width = self.inputWidthParam.value
//        }
//        
//        if self.inputHeightParam.valueDidChange
//        {
//            self.geometry.height = self.inputHeightParam.value
//        }
//        
//        if self.inputDepthParam.valueDidChange
//        {
//            self.geometry.depth = self.inputDepthParam.value
//        }
//        
//        if self.inputResolutionParam.valueDidChange
//        {
//            self.geometry.resolution =  self.inputResolutionParam.value
//        }
        
       return shouldOutputGeometry
     }
    
    private static func installedFonts() -> [String] {
        let fontFamilies = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return fontFamilies.sorted()
    }

}
