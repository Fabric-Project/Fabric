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

public class TesselatedTextGeometryNode : Node, NodeProtocol
{
    public static let name = "Tesellated Text Geometry"
    public static var nodeType = Node.NodeType.Geometery

    // Params
    public let inputTextParam:StringParameter
    public let inputFontParam:StringParameter
    public let inputResolutionParam:Int3Parameter
    public override var inputParameters: [any Parameter] { [inputTextParam, inputFontParam, inputResolutionParam] + super.inputParameters }

    // Ports
    public let outputGeometry:NodePort<Geometry>
    public override var ports:[any NodePortProtocol] {  [outputGeometry] + super.ports}

    private let geometry = TesselatedTextGeometry(text: "Testing", fontSize: 10.0)

    required public init(context: Context)
    {
        self.inputTextParam = StringParameter( "Text", "Testing", .inputfield)
        
        self.inputFontParam = StringParameter( "Font", "Helvetica", Self.installedFonts(), .dropdown)
        self.inputResolutionParam = Int3Parameter("Resolution", simd_int3(repeating: 1), .inputfield)

        self.outputGeometry = NodePort<Geometry>(name: Self.name, kind: .Outlet)

        super.init(context: context)
    }
        
    enum CodingKeys : String, CodingKey
    {
        case inputTextParameter
        case inputFontParameter
        case inputResolutionParameter
        case outputGeometryPort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputTextParam, forKey: .inputTextParameter)
        try container.encode(self.inputFontParam, forKey: .inputFontParameter)
        try container.encode(self.inputResolutionParam, forKey: .inputResolutionParameter)
        try container.encode(self.outputGeometry, forKey: .outputGeometryPort)
        
        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

//        self.inputWidthParam = try container.decode(FloatParameter.self, forKey: .inputWidthParameter)
//        self.inputHeightParam = try container.decode(FloatParameter.self, forKey: .inputHeightParameter)
//        self.inputDepthParam = try container.decode(FloatParameter.self, forKey: .inputDepthParameter)
        self.inputTextParam = try container.decode(StringParameter.self, forKey: .inputTextParameter)
        self.inputFontParam = try container.decode(StringParameter.self, forKey: .inputFontParameter)
        self.inputResolutionParam = try container.decode(Int3Parameter.self, forKey: .inputResolutionParameter)
        self.outputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .outputGeometryPort)
        
        self.inputFontParam.options = Self.installedFonts()
        
        try super.init(from: decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputTextParam.valueDidChange
        {
            self.geometry.text = self.inputTextParam.value
        }
        
        if self.inputFontParam.valueDidChange
        {
            self.geometry.fontName = self.inputFontParam.value
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
        
        self.outputGeometry.send(self.geometry)
     }
    
    private static func installedFonts() -> [String] {
        let fontFamilies = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return fontFamilies.sorted()
    }

}
