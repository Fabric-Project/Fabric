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
import UniformTypeIdentifiers
#if os(macOS)
import VideoToolbox
import MediaToolbox
#endif

private let MovieProviderNodeInitializer: Void = {

    print("One Time Global setup for MovieTextureNode")

    #if os(macOS)
    // Register professional video workflow codecs (ProRes, etc.) - macOS only
    VTRegisterProfessionalVideoWorkflowVideoDecoders()
    VTRegisterProfessionalVideoWorkflowVideoEncoders()
    MTRegisterProfessionalVideoWorkflowFormatReaders()
    #endif

}()

public class MovieProviderNode : Node, NodeFileLoadingProtocol
{
  
    public static var supportedContentTypes: [UTType] {
        if #available(iOS 26.0, macOS 26.0, *)
        {
            return AVURLAsset.audiovisualContentTypes.filter { $0.conforms(to: .movie) || $0.conforms(to: .video) }
        }
        
        return AVURLAsset.audiovisualMIMETypes()
            .compactMap { UTType(mimeType: $0) }
            .filter { $0.conforms(to: .movie) || $0.conforms(to: .video) }
    }

    public func setFileURL(_ url: URL) {
        self.inputFilePathParam.value = url.standardizedFileURL.absoluteString
    }

    override public class var name:String { "Movie Provider" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Play a Movie File from disk, providing a stream of output Images"}

    // Seek behaviour options. `frame` is exact (zero-tolerance) seek;
    // `keyframe` lets AVPlayer pick the nearest keyframe (default
    // `kCMTimePositiveInfinity` tolerance), which is faster and avoids
    // the brief stalls that exact seeks can trigger.
    public static let seekBehaviourFrame = "frame"
    public static let seekBehaviourKeyframe = "keyframe"
    public static let seekBehaviourOptions = [seekBehaviourFrame, seekBehaviourKeyframe]

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker, "Path to the movie file to play"))),
            ("inputPlayingParam", ParameterPort(parameter: BoolParameter("Playing", true, .toggle, "Play / pause the video"))),
            ("inputSeekTimeParam", ParameterPort(parameter: FloatParameter("Seek Time", -1.0, .inputfield, "Write a value to seek the player to that time (seconds). Setting to a different value seeks; setting to the same value is a no-op. Negative values are ignored on first load."))),
            ("inputSeekBehaviourParam", ParameterPort(parameter: StringParameter("Seek Behaviour", seekBehaviourKeyframe, seekBehaviourOptions, .dropdown, "How precisely seeks resolve — `frame` for an exact (zero-tolerance) seek, `keyframe` for AVPlayer's default fast seek to the nearest keyframe"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Current video frame")),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var inputPlayingParam:ParameterPort<Bool>     { port(named: "inputPlayingParam") }
    public var inputSeekTimeParam:ParameterPort<Float>   { port(named: "inputSeekTimeParam") }
    public var inputSeekBehaviourParam:ParameterPort<String> { port(named: "inputSeekBehaviourParam") }
    public var outputTexturePort:NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var url: URL? = nil
    @ObservationIgnored private var asset:AVURLAsset? = nil
    @ObservationIgnored private var player:AVPlayer = AVPlayer()
    @ObservationIgnored private var playerItem:AVPlayerItem? = nil
    @ObservationIgnored private var playerItemVideoOutput:AVPlayerItemVideoOutput
    @ObservationIgnored private var pixelBuffer:CVPixelBuffer? = nil
    @ObservationIgnored private var observer: Any? = nil

    /// Asset duration in seconds. Returns 0 until the asset's duration has
    /// loaded.
    public var duration: TimeInterval {
        guard let asset else { return 0 }
        let cmDuration = asset.duration
        let seconds = CMTimeGetSeconds(cmDuration)
        return seconds.isFinite ? seconds : 0
    }

    /// Player's current playback time in seconds.
    public var currentTime: TimeInterval {
        let cmTime = self.player.currentTime()
        let seconds = CMTimeGetSeconds(cmTime)
        return seconds.isFinite ? seconds : 0
    }

    /// `true` while a seek is in flight. Read-only. Embedders should
    /// avoid writing fresh values to `inputSeekTimeParam` while this
    /// is set — a player mid-seek still reports a stale `currentTime`
    /// briefly, and re-driving the seek port on every frame would
    /// cancel the previous seek and stall playback at the boundary.
    public var isSeeking: Bool { self.seeking }

    @ObservationIgnored private var seeking: Bool = false

    /// Internal seek implementation driven by `inputSeekTimeParam`
    /// changes in `execute`. Tolerance is selected from
    /// `inputSeekBehaviourParam`. Re-primes playback (`player.play()`)
    /// when the user wants the player playing — some seeks (notably
    /// zero-tolerance ones) leave `rate` at 0 momentarily, which would
    /// otherwise stall the player at the seek target.
    private func performSeek(to seconds: TimeInterval)
    {
        guard self.player.currentItem != nil else { return }
        let clamped = max(0, min(seconds, self.duration))
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        let mode = self.inputSeekBehaviourParam.value ?? Self.seekBehaviourKeyframe
        let tol: CMTime = (mode == Self.seekBehaviourFrame) ? .zero : .positiveInfinity
        self.seeking = true
        self.player.seek(to: target, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            self?.seeking = false
        }
        if (self.inputPlayingParam.value ?? true)
        {
            self.player.play()
        }
    }
    
    required public init(context:Context)
    {
        // Forces the initialization when the class is accessed
        _ = MovieProviderNodeInitializer
        
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        super.init(context: context)
    }
    
    public required init(context: Satin.Context, fileURL: URL) throws
    {
        // Forces the initialization when the class is accessed
        _ = MovieProviderNodeInitializer
        
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        super.init(context: context)
        
        self.setFileURL(fileURL)
    }
    
    
    required public init(from decoder: any Decoder) throws
    {
        // Forces the initialization when the class is accessed
        _ = MovieProviderNodeInitializer

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

        if self.inputPlayingParam.valueDidChange
        {
            if (self.inputPlayingParam.value ?? true)
            {
                self.player.play()
            }
            else
            {
                self.player.pause()
            }
        }

        // Honour seek port. Negative values are the sentinel default —
        // ignored so the asset isn't seeked to 0 on first load. Skip
        // when the player is already at the target (a same-target write
        // arriving while the player happens to be there is a no-op),
        // but always seek when the player's actual position differs.
        // This is what makes loop-back enforcement work: every time the
        // player crosses `outPoint`, the embedder re-writes `inPoint` to
        // this port and we genuinely re-seek.
        if self.inputSeekTimeParam.valueDidChange,
           let raw = self.inputSeekTimeParam.value,
           raw >= 0
        {
            let target = TimeInterval(raw)
            if abs(target - self.currentTime) > 0.05
            {
                performSeek(to: target)
            }
        }

        let time =  context.timing.time
        let itemTime = self.playerItemVideoOutput.itemTime(forHostTime: time)

        // While paused, AVPlayerItemVideoOutput stops emitting fresh pixel
        // buffers — so a seek-while-paused needs an explicit `copy` at the
        // current item time to push the new frame downstream.
        if self.playerItemVideoOutput.hasNewPixelBuffer(forItemTime: itemTime)
        {
            if let pixelBuffer = self.playerItemVideoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
               let renderer = context.graphRenderer,
               let image = renderer.newImage(fromPixelBuffer: pixelBuffer)
            {
                self.outputTexturePort.send( image )
            }
        }
        else if self.player.rate == 0,
                let item = self.player.currentItem
        {
            let pausedTime = item.currentTime()
            if let pixelBuffer = self.playerItemVideoOutput.copyPixelBuffer(forItemTime: pausedTime, itemTimeForDisplay: nil),
               let renderer = context.graphRenderer,
               let image = renderer.newImage(fromPixelBuffer: pixelBuffer)
            {
                self.outputTexturePort.send( image )
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
//        let colorPropertySettings = [
//                   AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
//                   AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
//                   AVVideoTransferFunctionKey: AVVideoTransferFunction_Linear
//               ]
      
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
                if (self.inputPlayingParam.value ?? true)
                {
                    self.player.play()
                }
                else
                {
                    self.player.pause()
                }
            }
            else
            {
                self.outputTexturePort.send( nil )

                print("wtf")
            }
        }
    }
}
