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
    public override class var nodeDescription: String { "Generates extruded 3D text geometry" }

    // Ports
    public let inputText = ParameterPort(parameter:StringParameter("Text", "Testing", .inputfield, "The text string to render as 3D extruded geometry"))
    public let inputFont = ParameterPort(parameter:StringParameter("Font", "Helvetica", ExtrudedTextGeometryNode.installedFonts(), .dropdown, "Font family to use for text rendering"))
    public let inputPieceGeneration = ParameterPort(parameter:StringParameter("Pieces", TesselatedTextGeometry.PieceGeneration.none.menuTitle, TesselatedTextGeometry.PieceGeneration.menuTitles, .dropdown, "Divides the text into pieces, one per sentence, word or character, for Transform Pieces and Piece Info. None draws the text as one piece"))

    override public func declaredPorts() -> [PortDeclaration]
    {
        [
            PortDeclaration(key: "inputText", port: self.inputText),
            PortDeclaration(key: "inputFont", port: self.inputFont),
            PortDeclaration(key: "inputPieceGeneration", port: self.inputPieceGeneration),
        ] + super.declaredPorts()
    }

    public override var geometry: ExtrudedTextGeometry { _geometry }

    private lazy var _geometry = ExtrudedTextGeometry(context:self.context, text: "Testing", fontSize: 1.0)

    override public func startExecution(renderer: GraphRenderer) throws
    {
        if let fontParam = self.inputFont.parameter as? StringParameter
        {
            fontParam.options = Self.installedFonts()
        }
        try super.startExecution(renderer: renderer)
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

        if self.inputPieceGeneration.valueDidChange,
           let pieceGeneration = TesselatedTextGeometry.PieceGeneration(menuTitle: self.inputPieceGeneration.value)
        {
            self.geometry.pieceGeneration = pieceGeneration
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
