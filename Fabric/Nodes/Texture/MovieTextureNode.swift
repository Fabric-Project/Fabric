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
    
    print("One Time Global setup for MovieTextureNode")
    
    VTRegisterProfessionalVideoWorkflowVideoDecoders()
    VTRegisterProfessionalVideoWorkflowVideoEncoders()
    MTRegisterProfessionalVideoWorkflowFormatReaders()
   
}()

public class MovieTextureNode : Node
{
    override public class var name:String { "Movie Provider" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Play a Movie File from disk, providing an output Image"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker))),
            ("outputTexturePort", NodePort<EquatableTexture>(name: "Image", kind: .Outlet)),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var outputTexturePort:NodePort<EquatableTexture> { port(named: "outputTexturePort") }
    
    @ObservationIgnored private var url: URL? = nil
    @ObservationIgnored private var asset:AVURLAsset? = nil
    @ObservationIgnored private var player:AVPlayer = AVPlayer()
    @ObservationIgnored private var playerItem:AVPlayerItem? = nil
    @ObservationIgnored private var playerItemVideoOutput:AVPlayerItemVideoOutput
    @ObservationIgnored private var pixelBuffer:CVPixelBuffer? = nil
    @ObservationIgnored private var textureCache:CVMetalTextureCache?
    @ObservationIgnored private var observer: Any? = nil
    
    required public init(context:Context)
    {
        // Forces the initialization when the class is accessed
        _ = MovieTextureNodeInitializer
        
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                                nil,
                                                context.device,
                                                nil,
                                                &self.textureCache)
        
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        super.init(context: context)
    }
    
    
    required public init(from decoder: any Decoder) throws
    {
        // Forces the initialization when the class is accessed
        _ = MovieTextureNodeInitializer

        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                          nil,
                                          decodeContext.documentContext.device,
                                          nil,
                                          &self.textureCache)
        
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true
        
        try super.init(from:decoder)
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputFilePathParam.valueDidChange
        {
            loadAssetFromInputValue()
        }
        
        let time =  context.timing.time
        let itemTime = self.playerItemVideoOutput.itemTime(forHostTime: time)
        
        if self.playerItemVideoOutput.hasNewPixelBuffer(forItemTime: itemTime)
        {
            if let pixelBuffer = self.playerItemVideoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
            {
                    CVMetalTextureCacheFlush(self.textureCache!, 0)
                    
                    var texture:CVMetalTexture? = nil
                    
                    let success = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                            self.textureCache!,
                                                                            pixelBuffer,
                                                                            nil,
                                                                            .bgra8Unorm,
                                                                            CVPixelBufferGetWidth(pixelBuffer),
                                                                            CVPixelBufferGetHeight(pixelBuffer),
                                                                            0,
                                                                            &texture)
                    
                    if success == kCVReturnSuccess && texture != nil
                    {
                        let latestFrameTexture = CVMetalTextureGetTexture(texture!)!
                        
                        self.outputTexturePort.send( EquatableTexture(texture: latestFrameTexture) )
                    }
//                }
            }
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
                   AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                   AVVideoTransferFunctionKey: AVVideoTransferFunction_Linear
               ]
      
        return [
            String(kCVPixelBufferPixelFormatTypeKey) : Int( kCVPixelFormatType_32BGRA ),
            String(kCVPixelBufferMetalCompatibilityKey) : true,
            String(kCVPixelBufferIOSurfacePropertiesKey) : [:],
//            AVVideoColorPropertiesKey : colorPropertySettings,
//            AVVideoAllowWideColorKey : true,
        ] as [String : Any]
    }
    
    private func loadAssetFromInputValue()
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false && self.url != URL(string: path)
        {
            self.url = URL(string: path)
            
            if let url,
                FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false) )
            {
                if let observer = self.observer
                {
                    NotificationCenter.default.removeObserver(observer)
                }
                
                self.player.pause()
                
                if let playerItem = self.player.currentItem
                {
                    playerItem.remove(self.playerItemVideoOutput)
                }
                
                self.asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                
                
                let playerItem = AVPlayerItem(asset: self.asset!, automaticallyLoadedAssetKeys: ["tracks", "metadata", "duration"])
                
                playerItem.preferredForwardBufferDuration = 0.5
                playerItem.add(self.playerItemVideoOutput)
                
                self.observer = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                       object:playerItem,
                                                       queue:OperationQueue.main) { note in

                    self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    self.player.play()
                }

                self.player.replaceCurrentItem(with: playerItem)

                self.player.volume = 0.0
                self.player.actionAtItemEnd = .none
                self.player.play()
            }
            else
            {
                self.outputTexturePort.send( nil )

                print("wtf")
            }
        }
    }
}
