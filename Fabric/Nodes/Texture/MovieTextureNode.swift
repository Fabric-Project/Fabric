//
//  HDRTextureNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal
import AVFoundation
import VideoToolbox
import MediaToolbox

private let MovieTextureNodeInitializer: Void = {
    
    print("Global setup for VideoSourceAssetMonitorInitializer")
    // One-time setup code here
    VTRegisterProfessionalVideoWorkflowVideoDecoders()
    VTRegisterProfessionalVideoWorkflowVideoEncoders()
    MTRegisterProfessionalVideoWorkflowFormatReaders()
   
}()

public class MovieTextureNode : Node
{
    public override class var name:String { "Movie Player" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }

    // Parameters
    let inputFilePathParam:StringParameter
    override public var inputParameters: [any Parameter] { [self.inputFilePathParam] + super.inputParameters}

    // Ports
    let outputTexturePort:NodePort<EquatableTexture>
    override public var ports:[AnyPort] { [outputTexturePort] + super.ports }


    private var texture: (any MTLTexture)? = nil
    
    
    private var url: URL? = nil
    private var asset:AVURLAsset? = nil
    private var player:AVPlayer = AVPlayer()
    private var playerItemVideoOutput:AVPlayerItemOutput
    
    required public init(context:Context)
    {
        // Forces the initialization when the class is accessed
        _ = MovieTextureNodeInitializer

        self.inputFilePathParam = StringParameter("File Path", "", .filepicker)
        self.outputTexturePort = NodePort<EquatableTexture>(name: "Image", kind: .Outlet)

        
        
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputFilePathParameter
        case outputTexturePort
    }
    
    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputFilePathParam, forKey: .inputFilePathParameter)
        try container.encode(self.outputTexturePort, forKey: .outputTexturePort)

        try super.encode(to: encoder)
    }
    
    required public init(from decoder: any Decoder) throws
    {
        // Forces the initialization when the class is accessed
        _ = MovieTextureNodeInitializer

        let container = try decoder.container(keyedBy: CodingKeys.self)

        
        self.inputFilePathParam = try container.decode(StringParameter.self, forKey: .inputFilePathParameter)
        self.outputTexturePort = try container.decode(NodePort<EquatableTexture>.self, forKey: .outputTexturePort)
        
        
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {

        if let texture = self.texture
        {
            self.outputTexturePort.send( EquatableTexture(texture: texture) )
        }
        else
        {
            self.outputTexturePort.send( nil )
        }
     }

    
    private static func playerOutputSettings() -> [String : Any]
    {
        // HD
//        let colorPropertySettings = [
//            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
//            AVVideoYCbCrMatrixKey: AVVideoTransferFunction_ITU_R_709_2,
//            AVVideoTransferFunctionKey: AVVideoYCbCrMatrix_ITU_R_709_2
//        ]
        
        // HD Wide Gamut
//        let colorPropertySettings = [
//            AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
//            AVVideoYCbCrMatrixKey: AVVideoTransferFunction_ITU_R_709_2,
//            AVVideoTransferFunctionKey: AVVideoYCbCrMatrix_ITU_R_709_2
//        ]
        
        // Linear
        let colorPropertySettings = [
                   AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                   AVVideoYCbCrMatrixKey: AVVideoTransferFunction_Linear,
                   AVVideoTransferFunctionKey: AVVideoYCbCrMatrix_ITU_R_709_2
               ]
      
        return [
            String(kCVPixelBufferPixelFormatTypeKey) : Int( kCVPixelFormatType_32BGRA ),
            String(kCVPixelBufferMetalCompatibilityKey) : true,
            String(kCVPixelBufferIOSurfacePropertiesKey) : [:],
//            AVVideoColorPropertiesKey : colorPropertySettings,
//            AVVideoAllowWideColorKey : true,
        ] as [String : Any]
    }
}
