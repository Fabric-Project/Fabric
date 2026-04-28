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
#if FABRIC_HAP_ENABLED
import HapInAVFoundation
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

#if FABRIC_HAP_ENABLED
    /// Hap decoder output, present only while the loaded asset is a
    /// Hap-encoded movie. When non-nil, the standard
    /// `playerItemVideoOutput` is *not* attached to the player item.
    @ObservationIgnored private var hapOutput: AVPlayerItemHapDXTOutput? = nil
    /// `true` when the loaded codec is one we can upload as a Metal
    /// compressed texture (BC1 / BC3 / BC7) directly from the
    /// HapDecoderFrame's DXT bytes — no RGB pixel walk, no memcpy of
    /// uncompressed pixels. `false` falls back to the RGB output path
    /// for codecs that need post-processing (YCoCg / multi-plane / HDR).
    @ObservationIgnored private var hapUsesDXTPath: Bool = false
#endif

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

        let time = context.timing.time

#if FABRIC_HAP_ENABLED
        // Hap path. Two flavours:
        //   - DXT direct upload (Hap1 / Hap5 / Hap7): the decompressed
        //     bytes are already in a Metal-compatible BC1/BC3/BC7
        //     compressed format. We allocate a compressed MTLTexture
        //     and upload via `replaceRegion` — no CPU pixel walk, no
        //     8MB memcpy, ~6× less GPU upload bandwidth than RGBA.
        //   - RGB fallback (HapY / HapM / HapH / HapA): decoder
        //     emitted RGBA bytes, copy into a CVPixelBuffer like the
        //     standard AVPlayerItemVideoOutput path.
        if let hapOutput = self.hapOutput,
           let renderer = context.graphRenderer
        {
            let itemTime = hapOutput.itemTime(forHostTime: time)
            guard let frame = hapOutput.allocFrameClosest(to: itemTime) else { return }
            if self.hapUsesDXTPath,
               let image = Self.makeDXTImage(fromHapFrame: frame, device: renderer.context.device)
            {
                self.outputTexturePort.send( image )
            }
            else if let pixelBuffer = Self.makePixelBuffer(fromHapFrame: frame),
                    let image = renderer.newImage(fromPixelBuffer: pixelBuffer)
            {
                self.outputTexturePort.send( image )
            }
            return
        }
#endif

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

#if FABRIC_HAP_ENABLED
    // FourCharCode constants from HapInAVFoundation's
    // HapCodecSubTypes.h / PixelFormats.h. Inlined here because
    // Swift's C importer drops multi-char `#define`s like
    // `#define kHapCodecSubType 'Hap1'`.
    private static let hapCodec_Hap1: OSType  = 0x48617031   // 'Hap1'
    private static let hapCodec_Hap5: OSType  = 0x48617035   // 'Hap5'
    private static let hapCodec_Hap7: OSType  = 0x48617037   // 'Hap7'
    private static let hapPixFmt_DXt1: OSType = 0x44587431   // 'DXt1' RGB DXT1
    private static let hapPixFmt_DXT5: OSType = 0x44585435   // 'DXT5' RGBA DXT5
    private static let hapPixFmt_BC7A: OSType = 0x42433741   // 'BC7A' RGBA BC7

    /// Decide whether `track`'s codec can take the DXT direct-upload
    /// fast path. Hap (Hap1), Hap Alpha (Hap5), and Hap 7 (Hap7) map
    /// straight to BC1/BC3/BC7 Metal compressed formats. The other
    /// Hap variants (HapY YCoCg, HapM multi-plane, HapH HDR, HapA
    /// alpha-only) need post-processing or shader-side colour-space
    /// conversion that this node doesn't perform — those go through
    /// the slower RGB fallback.
    private static func codecSupportsDirectDXTUpload(in track: AVAssetTrack) -> Bool {
        for desc in track.formatDescriptions {
            let cmDesc = desc as! CMFormatDescription
            switch CMFormatDescriptionGetMediaSubType(cmDesc) {
            case hapCodec_Hap1, hapCodec_Hap5, hapCodec_Hap7:
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Map a Hap CV pixel format (`kHapCVPixelFormat_*`) to the
    /// equivalent Metal compressed-texture format. Returns `nil` for
    /// formats that need additional processing (YCoCg → RGB shader,
    /// multi-plane planar formats, BC6 HDR).
    private static func metalFormat(forHapDXT osType: OSType) -> MTLPixelFormat? {
        switch osType {
        case hapPixFmt_DXt1: return .bc1_rgba
        case hapPixFmt_DXT5: return .bc3_rgba
        case hapPixFmt_BC7A: return .bc7_rgbaUnorm
        default:             return nil
        }
    }

    /// Performant path: turn a HapDecoderFrame's pre-decompressed DXT
    /// bytes into a compressed MTLTexture in one upload. No RGB
    /// expansion, no memcpy of decompressed pixels.
    ///
    /// Trade-off: a fresh MTLTexture is allocated per frame. Metal's
    /// allocator handles this well at 60fps for typical Hap frame
    /// sizes (~0.5–2MB compressed); a texture pool would be a
    /// follow-up optimisation if profiling shows allocator pressure.
    private static func makeDXTImage(fromHapFrame frame: HapDecoderFrame, device: MTLDevice) -> FabricImage? {
        // Hap Q Alpha is encoded as two planes (BC3 + RGTC1). The
        // single-plane Metal upload path here doesn't handle that;
        // those frames fall back via `outputAsRGB` at asset load.
        guard frame.dxtPlaneCount == 1 else { return nil }
        guard let mtlFormat = metalFormat(forHapDXT: frame.dxtPixelFormats[0]) else { return nil }

        let dxtSize = frame.dxtImgSize
        let width = Int(dxtSize.width)
        let height = Int(dxtSize.height)
        guard width > 0, height > 0 else { return nil }

        let dxtData = frame.dxtDatas[0]
        guard dxtData != nil else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mtlFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        // BC formats can't be render targets or shader writes — only
        // sampled. Storage `.shared` keeps the upload a single
        // CPU→GPU copy on UMA hardware (Apple Silicon).
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        // BC1 packs a 4×4 block in 8 bytes; BC3 / BC7 in 16 bytes.
        let blocksPerRow = (width + 3) / 4
        let bytesPerBlock = (mtlFormat == .bc1_rgba) ? 8 : 16
        let bytesPerRow = blocksPerRow * bytesPerBlock

        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: dxtData!, bytesPerRow: bytesPerRow)

        return FabricImage.unmanaged(texture: texture)
    }

    /// Copy the Hap decoder frame's RGB bytes into a freshly-allocated
    /// Metal-compatible CVPixelBuffer. Used as a fallback when the DXT
    /// fast path can't handle the codec (YCoCg, multi-plane, HDR).
    /// We don't share the HapDecoderFrame's buffer across frames —
    /// copying once per frame avoids Swift / CF lifetime gymnastics
    /// around the Obj-C `alloc*` return convention.
    private static func makePixelBuffer(fromHapFrame frame: HapDecoderFrame) -> CVPixelBuffer? {
        guard let rgbData = frame.rgbData else { return nil }
        let width = Int(frame.rgbImgSize.width)
        let height = Int(frame.rgbImgSize.height)
        guard width > 0, height > 0, frame.rgbDataSize > 0 else { return nil }

        let attrs: CFDictionary = [
            kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey: NSNumber(value: true),
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        ] as CFDictionary

        var pb: CVPixelBuffer?
        let err = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                      kCVPixelFormatType_32BGRA, attrs, &pb)
        guard err == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let dst = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let dstStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let srcStride = frame.rgbDataSize / height
        let copyBytes = min(dstStride, srcStride)
        if dstStride == srcStride {
            // Fast path: tightly packed, single memcpy.
            memcpy(dst, rgbData, frame.rgbDataSize)
        } else {
            let src = rgbData.assumingMemoryBound(to: UInt8.self)
            let dstP = dst.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                memcpy(dstP.advanced(by: row * dstStride),
                       src.advanced(by: row * srcStride),
                       copyBytes)
            }
        }
        return pixelBuffer
    }
#endif

    
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

                if let oldItem = self.player.currentItem
                {
                    oldItem.remove(self.playerItemVideoOutput)
#if FABRIC_HAP_ENABLED
                    if let oldHap = self.hapOutput {
                        oldItem.remove(oldHap)
                    }
#endif
                }

                self.asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])


                let playerItem = AVPlayerItem(asset: self.asset!, automaticallyLoadedAssetKeys: ["tracks", "metadata", "duration"])

                playerItem.preferredForwardBufferDuration = 0.5
#if FABRIC_HAP_ENABLED
                // Hap-encoded movies use a dedicated decoder that emits
                // RGB pixel buffers via HapInAVFoundation. Falls back to
                // the standard AVPlayerItemVideoOutput for everything else.
                if self.asset?.containsHapVideoTrack() == true,
                   let hapTrack = self.asset?.hapVideoTracks().first as? AVAssetTrack,
                   let output = AVPlayerItemHapDXTOutput(hapAssetTrack: hapTrack) {
                    // Pick the live-performance fast path (DXT direct
                    // upload) when the codec supports it; otherwise the
                    // RGB conversion path covers the harder cases.
                    let useDXT = Self.codecSupportsDirectDXTUpload(in: hapTrack)
                    output.outputAsRGB = !useDXT
                    if !useDXT {
                        output.destRGBPixelFormat = OSType(kCVPixelFormatType_32BGRA)
                    }
                    output.suppressesPlayerRendering = true
                    playerItem.add(output)
                    self.hapOutput = output
                    self.hapUsesDXTPath = useDXT
                } else {
                    playerItem.add(self.playerItemVideoOutput)
                    self.hapOutput = nil
                    self.hapUsesDXTPath = false
                }
#else
                playerItem.add(self.playerItemVideoOutput)
#endif
                
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
