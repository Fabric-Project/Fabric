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

public class TesselatedTextGeometryNode : BaseGeometryNode
{
    public override class var name:String { "2D Text Geometry" }
    public override class var nodeDescription: String { "Generates tessellated 2D text geometry" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
        ("inputText", ParameterPort(parameter:StringParameter("Text", "Testing", .inputfield, "The text string to render as 2D geometry"))),
        ("inputFont", ParameterPort(parameter:StringParameter("Font", "Helvetica", Self.installedFonts(), .dropdown, "Font family to use for text rendering"))),
        ("inputPieceGeneration", ParameterPort(parameter:StringParameter("Pieces", TesselatedTextGeometry.PieceGeneration.none.menuTitle, TesselatedTextGeometry.PieceGeneration.menuTitles, .dropdown, "Divides the text into pieces, one per sentence, word or character, for Transform Pieces and Piece Info. None draws the text as one piece"))),

        ] + ports
    }
    
    // Proxy Ports
    public var inputText:ParameterPort<String> { port(named: "inputText")  }
    public var inputFont:ParameterPort<String> { port(named: "inputFont")  }
    public var inputPieceGeneration:ParameterPort<String> { port(named: "inputPieceGeneration")  }

    public override var geometry: TesselatedTextGeometry { _geometry }

    private lazy var _geometry = TesselatedTextGeometry(context:self.context, text: "Testing", fontSize: 1.0)

    override public func startExecution(renderer:GraphRenderer) throws {
        if let fontParam = self.inputFont.parameter as? StringParameter
        {
            fontParam.options = Self.installedFonts()
        }
        try super.startExecution(renderer: renderer)
    }
    
    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
    {
        var shouldOutputGeometry = false 
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

/// The Pieces menu shared by the 2D and 3D Text Geometry nodes: each case's title, in menu order.
extension TesselatedTextGeometry.PieceGeneration
{
    static let menuOrder: [Self] = [.none, .sentence, .word, .character]

    static var menuTitles: [String] { menuOrder.map(\.menuTitle) }

    var menuTitle: String
    {
        switch self
        {
        case .none: return "None"
        case .sentence: return "Sentence"
        case .word: return "Word"
        case .character: return "Character"
        }
    }

    init?(menuTitle: String?)
    {
        guard let match = Self.menuOrder.first(where: { $0.menuTitle == menuTitle }) else { return nil }
        self = match
    }
}
