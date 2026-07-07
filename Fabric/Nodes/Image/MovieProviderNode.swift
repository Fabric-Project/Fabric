//
//  HDRTextureNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import os
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

    MovieProviderNode.log.notice("One-time global codec registration for MovieProviderNode")

    #if os(macOS)
    // Register professional video workflow codecs (ProRes, etc.) - macOS only
    VTRegisterProfessionalVideoWorkflowVideoDecoders()
    VTRegisterProfessionalVideoWorkflowVideoEncoders()
    MTRegisterProfessionalVideoWorkflowFormatReaders()
    #endif

}()

public class MovieProviderNode : Node, NodeFileLoadingProtocol
{
    fileprivate static let log = Logger(subsystem: "graphics.fabric", category: "MovieProviderNode")

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

    /// Seek tolerance window, in seconds, passed directly to AVPlayer
    /// as `toleranceBefore` / `toleranceAfter`. Set at construction
    /// only; not exposed as a port.
    ///
    /// `.infinity` (the default) maps to `CMTime.positiveInfinity` —
    /// AVPlayer picks the nearest keyframe, the fastest option and
    /// the right default for most playback. `0` maps to `CMTime.zero`
    /// — exact frame-accurate seek, slower and can stall briefly. Any
    /// positive finite value lets AVPlayer settle within that many
    /// seconds of the requested target.
    public let seekTolerance: TimeInterval

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker, "Path to the movie file to play"))),
            ("inputPlayingParam", ParameterPort(parameter: BoolParameter("Playing", true, .toggle, "Play / pause the video"))),
            ("inputSeekTimeParam", ParameterPort(parameter: FloatParameter("Seek Time", -1.0, .inputfield, "Write a value to seek the player to that time (seconds). Setting to a different value seeks; setting to the same value is a no-op. Negative values are ignored on first load."))),
            ("inputVolumeParam", ParameterPort(parameter: FloatParameter("Volume", 0.0, 0.0, 1.0, .slider, "Audio playback volume where 0 is silent and 1 is full volume"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Current video frame")),
            ("outputCurrentTimePort", NodePort<Float>(name: "Current Time", kind: .Outlet, description: "Current movie playback time in seconds")),
            ("outputDurationPort", NodePort<Float>(name: "Duration", kind: .Outlet, description: "Movie duration in seconds")),
            ("outputNormalizedTimePort", NodePort<Float>(name: "Normalized Time", kind: .Outlet, description: "Current playback position normalized from 0 to 1")),
            ("outputDidPlayToEndPort", NodePort<Bool>(name: "Did Play To End", kind: .Outlet, description: "True for one execution pass when playback reaches the end")),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var inputPlayingParam:ParameterPort<Bool>     { port(named: "inputPlayingParam") }
    public var inputSeekTimeParam:ParameterPort<Float>   { port(named: "inputSeekTimeParam") }
    public var inputVolumeParam:ParameterPort<Float>     { port(named: "inputVolumeParam") }
    public var outputTexturePort:NodePort<FabricImage>   { port(named: "outputTexturePort") }
    public var outputCurrentTimePort:NodePort<Float>     { port(named: "outputCurrentTimePort") }
    public var outputDurationPort:NodePort<Float>        { port(named: "outputDurationPort") }
    public var outputNormalizedTimePort:NodePort<Float>  { port(named: "outputNormalizedTimePort") }
    public var outputDidPlayToEndPort:NodePort<Bool>     { port(named: "outputDidPlayToEndPort") }

    private var url: URL? = nil
    private var asset:AVURLAsset? = nil
    private var player:AVPlayer = AVPlayer()
    private var playerItem:AVPlayerItem? = nil
    private var playerItemVideoOutput:AVPlayerItemVideoOutput
    private var pixelBuffer:CVPixelBuffer? = nil
    private var observer: Any? = nil
    private var didPlayToEndPendingPulse: Bool = false

#if FABRIC_HAP_ENABLED
    /// Hap decoder output, present only while the loaded asset is a
    /// Hap-encoded movie. When non-nil, the standard
    /// `playerItemVideoOutput` is *not* attached to the player item.
    private var hapOutput: AVPlayerItemHapDXTOutput? = nil
    /// `true` when the loaded codec is one we can upload as a Metal
    /// compressed texture (BC1 / BC3 / BC7) directly from the
    /// HapDecoderFrame's DXT bytes — no RGB pixel walk, no memcpy of
    /// uncompressed pixels. `false` falls back to the RGB output path
    /// for codecs that need post-processing (YCoCg / multi-plane / HDR).
    private var hapUsesDXTPath: Bool = false

    /// Presentation time of the most recently emitted Hap frame.
    /// Used to dedupe successive `allocFrameClosest(to:)` returns —
    /// AVPlayerItemVideoOutput offers `hasNewPixelBuffer(forItemTime:)`
    /// for this on the standard path, but AVPlayerItemHapDXTOutput has
    /// no equivalent, so we gate on the frame's own PTS. Without the
    /// gate, every execute() tick re-uploads and re-emits the same
    /// frame, which burns GPU upload bandwidth and breaks
    /// `valueDidChange`-style edge detection in connected nodes.
    ///
    /// Initialised to `.invalid` so the first frame after asset load
    /// always emits — `CMTimeCompare`'s behaviour is undefined on
    /// `.invalid`, hence the explicit `isValid` check at the gate.
    ///
    /// `@ObservationIgnored` for the same reason as `seeking` —
    /// Hap frame timestamps may be inspected from the decoder's
    /// queue context in future refactors.
    private var lastEmittedHapTime: CMTime = .invalid

    /// One-shot flag so the BC-block-alignment fallback in
    /// `makeDXTImage` logs at most once per loaded asset, not once
    /// per frame. Re-armed at asset swap.
    private var didLogDXTSubBlockPadding: Bool = false
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

    private var normalizedTime: TimeInterval {
        let duration = self.duration
        guard duration > 0 else { return 0 }
        return max(0, min(self.currentTime / duration, 1))
    }

    private func volumeInputValue() -> Float {
        max(0, min(self.inputVolumeParam.value ?? 0, 1))
    }

    private func sendPlaybackInfo()
    {
        self.outputCurrentTimePort.send(Float(self.currentTime))
        self.outputDurationPort.send(Float(self.duration))
        self.outputNormalizedTimePort.send(Float(self.normalizedTime))

        if self.didPlayToEndPendingPulse
        {
            self.didPlayToEndPendingPulse = false
            self.outputDidPlayToEndPort.send(true, force: true)
        }
        else
        {
            self.outputDidPlayToEndPort.send(false, force: true)
        }
    }

    private func resetPlaybackInfo()
    {
        self.didPlayToEndPendingPulse = false
        self.outputCurrentTimePort.send(0, force: true)
        self.outputDurationPort.send(0, force: true)
        self.outputNormalizedTimePort.send(0, force: true)
        self.outputDidPlayToEndPort.send(false, force: true)
    }

    /// Whether a seek is in flight. Used internally by `performSeek`
    /// to coalesce concurrent seek requests (see `pendingSeekTarget`)
    /// and by `execute()` to know when to drain that pending target.
    ///
    /// `@ObservationIgnored` because the seek completion handler
    /// fires on an internal AVPlayer queue, off-main. Fabric's
    /// `@Observable` engine types are main-thread-affine — without
    /// the opt-out, the off-main write would be Observation UB.
    private var seeking: Bool = false

    /// Set by `performSeek`'s completion handler when the player is
    /// paused at seek-land time, cleared after the next `execute()`
    /// emit attempt. AVPlayerItemVideoOutput stops emitting fresh
    /// pixel buffers while the player is paused, so without this
    /// one-shot the seeked-to frame would never reach downstream
    /// consumers until playback resumed.
    ///
    /// Threading note as per `seeking` — written from AVFoundation's
    /// internal queue, so `@ObservationIgnored`.
    private var needsEmitAfterSeek: Bool = false

    /// Coalesce-buffer for seek targets arriving while a previous seek
    /// is still in flight. Written from `performSeek` on the consumer
    /// queue; drained from `execute()` once `seeking` clears. Only the
    /// latest value survives — intermediate targets are dropped, which
    /// is the point: a seek-storm of nearby targets resolves to one
    /// final seek to the latest, not N cancelled+restarted seeks.
    private var pendingSeekTarget: TimeInterval? = nil

    /// Internal seek implementation driven by `inputSeekTimeParam`
    /// changes in `execute`. Tolerance comes from `seekTolerance`
    /// (set at init). Re-primes playback (`player.play()`) when the
    /// user wants the player playing — some seeks (notably zero-
    /// tolerance ones) leave `rate` at 0 momentarily, which would
    /// otherwise stall the player at the seek target.
    ///
    /// If a seek is already in flight, the new target is stashed in
    /// `pendingSeekTarget` and the drain in `execute()` re-issues it
    /// after the in-flight seek lands. Avoids cancelling the in-flight
    /// seek (which would stall playback) and bounds backlog to one.
    private func performSeek(to seconds: TimeInterval)
    {
        // Coalesce: while a seek is in flight, just record the latest
        // target. execute() drains it once `seeking` clears.
        if self.seeking
        {
            self.pendingSeekTarget = seconds
            return
        }
        guard self.player.currentItem != nil else { return }
        let clamped = max(0, min(seconds, self.duration))
        // Build the seek time on the video track's natural timescale
        // so frame-accurate seeks land on actual sample boundaries.
        // Falls back to 600 (a common timebase) when no video track
        // is available — e.g. asset still loading.
        let timescale = self.asset?.tracks(withMediaType: .video).first?.naturalTimeScale ?? 600
        let target = CMTime(seconds: clamped, preferredTimescale: timescale)
        let tol: CMTime = self.seekTolerance.isInfinite
            ? .positiveInfinity
            : CMTime(seconds: self.seekTolerance, preferredTimescale: timescale)
        self.seeking = true
        self.player.seek(to: target, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            guard let self else { return }
            self.seeking = false
            // If the player is paused at seek-land time,
            // AVPlayerItemVideoOutput won't emit a fresh pixel buffer
            // on its own — flag the next execute() to push the seeked
            // frame downstream as a one-shot.
            if self.player.rate == 0
            {
                self.needsEmitAfterSeek = true
            }
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

        self.seekTolerance = .infinity
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        super.init(context: context)
    }

    /// Construct with a custom seek tolerance. Pass `0` for exact
    /// frame-accurate seeks, `.infinity` for fastest keyframe seeks
    /// (the default of the other initialisers), or a positive finite
    /// value to let AVPlayer settle within that many seconds.
    public init(context: Context, seekTolerance: TimeInterval)
    {
        // Forces the initialization when the class is accessed
        _ = MovieProviderNodeInitializer

        self.seekTolerance = seekTolerance
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        super.init(context: context)
    }

    public required init(context: Satin.Context, fileURL: URL) throws
    {
        // Forces the initialization when the class is accessed
        _ = MovieProviderNodeInitializer

        self.seekTolerance = .infinity
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        super.init(context: context)

        self.setFileURL(fileURL)
    }


    required public init(from decoder: any Decoder) throws
    {
        // Forces the initialization when the class is accessed
        _ = MovieProviderNodeInitializer

        self.seekTolerance = .infinity
        self.playerItemVideoOutput = AVPlayerItemVideoOutput(outputSettings: Self.playerOutputSettings() )
        self.playerItemVideoOutput.suppressesPlayerRendering = true

        try super.init(from:decoder)
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
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

        if self.inputVolumeParam.valueDidChange
        {
            self.player.volume = self.volumeInputValue()
        }

        // Honour seek port. Negative values are the sentinel default —
        // ignored so the asset isn't seeked to 0 on first load.
        // `valueDidChange` already filters identical writes, and in
        // frame mode the user has explicitly asked for frame-accurate
        // tracking — so we don't second-guess a different-target write
        // with a magic-number tolerance.
        if self.inputSeekTimeParam.valueDidChange,
           let raw = self.inputSeekTimeParam.value,
           raw >= 0
        {
            performSeek(to: TimeInterval(raw))
        }

        // Drain any pending seek queued while a previous seek was in
        // flight. Latest target wins; intermediate targets were
        // dropped at coalesce time inside performSeek.
        if !self.seeking, let pending = self.pendingSeekTarget
        {
            self.pendingSeekTarget = nil
            performSeek(to: pending)
        }

        let time = executionInfo.timing.time
        self.sendPlaybackInfo()

#if FABRIC_HAP_ENABLED
        if self.executeHapPath(renderer: renderer, hostTime: time) { return }
#endif

        let itemTime = self.playerItemVideoOutput.itemTime(forHostTime: time)

        if self.playerItemVideoOutput.hasNewPixelBuffer(forItemTime: itemTime)
        {
            if let pixelBuffer = self.playerItemVideoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
               let image = renderer.newImage(fromPixelBuffer: pixelBuffer)
            {
                self.outputTexturePort.send( image )
            }
        }
        else if self.needsEmitAfterSeek,
                let item = self.player.currentItem
        {
            // One-shot: a seek landed while paused. Copy the player's
            // current frame and push it; downstream then holds it
            // until playback resumes or another seek lands.
            self.needsEmitAfterSeek = false
            let pausedTime = item.currentTime()
            if let pixelBuffer = self.playerItemVideoOutput.copyPixelBuffer(forItemTime: pausedTime, itemTimeForDisplay: nil),
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

    private func unloadCurrentAsset()
    {
        if let observer = self.observer
        {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }

        self.player.pause()

        if let oldItem = self.player.currentItem
        {
            oldItem.remove(self.playerItemVideoOutput)
#if FABRIC_HAP_ENABLED
            if let oldHap = self.hapOutput
            {
                oldItem.remove(oldHap)
            }
#endif
        }

        self.player.replaceCurrentItem(with: nil)
        self.asset = nil
        self.url = nil
        self.outputTexturePort.send(nil)
        self.resetPlaybackInfo()

#if FABRIC_HAP_ENABLED
        self.hapOutput = nil
        self.hapUsesDXTPath = false
        self.lastEmittedHapTime = .invalid
        self.didLogDXTSubBlockPadding = false
#endif
    }

    private func loadAssetFromInputValue()
    {
        guard let path = self.inputFilePathParam.value,
              path.isEmpty == false
        else
        {
            self.unloadCurrentAsset()
            return
        }

        if self.url != URL(string: path)
        {
            self.url = URL(string: path)

            if let url,
                FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false) )
            {
                self.unloadCurrentAsset()
                self.url = url

#if FABRIC_HAP_ENABLED
                // New asset's clock is independent of the previous
                // one — clear the Hap dedupe gate so the first frame
                // of the new asset always emits regardless of whether
                // its PTS happens to coincide with the last emit.
                // Also re-arm the per-asset BC-padding log so a
                // newly-loaded sub-block-aligned asset gets its own
                // hint.
                self.lastEmittedHapTime = .invalid
                self.didLogDXTSubBlockPadding = false
#endif

                self.asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])


                let playerItem = AVPlayerItem(asset: self.asset!, automaticallyLoadedAssetKeys: ["tracks", "metadata", "duration"])

                playerItem.preferredForwardBufferDuration = 0.5
#if FABRIC_HAP_ENABLED
                if !self.attachHapOutput(to: playerItem, url: url)
                {
                    playerItem.add(self.playerItemVideoOutput)
                    print("MovieProviderNode: AVPlayerItemVideoOutput path engaged for \"\(url.lastPathComponent)\"")
                }
#else
                playerItem.add(self.playerItemVideoOutput)
                print("MovieProviderNode: AVPlayerItemVideoOutput path engaged for \"\(url.lastPathComponent)\"")
#endif

                self.observer = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                       object:playerItem,
                                                       queue:OperationQueue.main) { [weak self] _ in

                    guard let self else { return }
                    self.didPlayToEndPendingPulse = true
                    self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    self.player.play()
                }

                self.player.replaceCurrentItem(with: playerItem)

                self.player.volume = self.volumeInputValue()
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
                let invalidURL = self.url
                self.unloadCurrentAsset()
                Self.log.error("Movie file not found at \(invalidURL?.path() ?? "<nil>", privacy: .public)")
            }
        }
    }

#if FABRIC_HAP_ENABLED
    /// Emit the current frame via the Hap decoder when one is attached.
    ///
    /// Returns `true` when this node is configured for Hap playback
    /// (the standard `AVPlayerItemVideoOutput` path should be skipped),
    /// `false` when there's no Hap output for this asset (caller falls
    /// through to the standard path).
    ///
    /// Two flavours of Hap emit:
    ///   - DXT direct upload (Hap1 / Hap5 / Hap7): the decompressed
    ///     bytes are already in a Metal-compatible BC1/BC3/BC7
    ///     compressed format. We allocate a compressed MTLTexture and
    ///     upload via `replaceRegion` — no CPU pixel walk, no 8MB
    ///     memcpy, ~6× less GPU upload bandwidth than RGBA.
    ///   - RGB fallback (HapY / HapM / HapH / HapA): decoder emits
    ///     RGBA bytes; copy into a CVPixelBuffer like the standard
    ///     AVPlayerItemVideoOutput path.
    private func executeHapPath(renderer: GraphRenderer, hostTime: CFTimeInterval) -> Bool
    {
        guard let hapOutput = self.hapOutput
        else { return false }

        let itemTime = hapOutput.itemTime(forHostTime: hostTime)
        guard let frame = hapOutput.allocFrameClosest(to: itemTime) else { return true }

        // Dedupe successive frames at the same presentation time.
        // `allocFrameClosest(to:)` happily returns the same frame on
        // back-to-back ticks (the decoder's notion of "closest" doesn't
        // care that we just emitted that frame). `CMTimeCompare`'s
        // behaviour is undefined on `.invalid`, hence the explicit
        // `isValid` check for the first-frame-after-load case.
        //
        // A pending post-seek emit (set by `performSeek`'s completion
        // handler when the player was paused on seek-land) bypasses
        // the gate: AVPlayer holding `rate == 0` can yield a frame at
        // the same PTS as the previously emitted one and we still
        // want it pushed, since downstream may be holding a stale
        // frame from before the seek. This is the Hap-path analogue
        // of the non-Hap `else if needsEmitAfterSeek` branch below —
        // executeHapPath returns before that branch is reachable, so
        // without this consume the flag would be set and never cleared
        // on Hap assets.
        let isAfterSeekEmit = self.needsEmitAfterSeek
        if !isAfterSeekEmit,
           self.lastEmittedHapTime.isValid,
           CMTimeCompare(frame.presentationTime, self.lastEmittedHapTime) == 0
        {
            return true
        }
        if isAfterSeekEmit
        {
            self.needsEmitAfterSeek = false
        }

        var emitted = false
        if self.hapUsesDXTPath,
           let image = self.makeDXTImage(fromHapFrame: frame, renderer: renderer)
        {
            self.outputTexturePort.send( image )
            emitted = true
        }
        else if let pixelBuffer = Self.makePixelBuffer(fromHapFrame: frame),
                let image = renderer.newImage(fromPixelBuffer: pixelBuffer)
        {
            self.outputTexturePort.send( image )
            emitted = true
        }
        if emitted
        {
            self.lastEmittedHapTime = frame.presentationTime
        }
        return true
    }

    /// Attach a Hap DXT decoder output to `playerItem` when the loaded
    /// asset is Hap-encoded. Returns `true` when a Hap output was
    /// attached (caller skips the standard `AVPlayerItemVideoOutput`
    /// path), `false` when the asset is not Hap or output construction
    /// failed (caller falls through to the standard path).
    ///
    /// Picks the live-performance fast path (DXT direct upload) when
    /// the codec supports it (Hap1 / Hap5 / Hap7); otherwise switches
    /// the decoder to RGB output and logs a hint, since RGB conversion
    /// does a CPU pixel walk + full uncompressed upload per frame.
    private func attachHapOutput(to playerItem: AVPlayerItem, url: URL) -> Bool
    {
        guard self.asset?.containsHapVideoTrack() == true,
              let hapTrack = self.asset?.hapVideoTracks().first as? AVAssetTrack,
              let output = AVPlayerItemHapDXTOutput(hapAssetTrack: hapTrack)
        else {
            self.hapOutput = nil
            self.hapUsesDXTPath = false
            return false
        }

        let useDXT = Self.codecSupportsDirectDXTUpload(in: hapTrack)
        output.outputAsRGB = !useDXT
        let codec = Self.hapCodecLabel(for: hapTrack) ?? "unknown Hap"
        if useDXT {
            print("MovieProviderNode: Hap DXT direct upload path engaged for \"\(url.lastPathComponent)\" (codec \(codec))")
        } else {
            output.destRGBPixelFormat = OSType(kCVPixelFormatType_32BGRA)
            Self.log.notice("Hap RGB fallback path engaged for \"\(url.lastPathComponent, privacy: .public)\" (codec \(codec, privacy: .public)). Re-encode as Hap, Hap Alpha, or Hap 7 for the DXT direct-upload fast path.")
        }
        output.suppressesPlayerRendering = true
        playerItem.add(output)
        self.hapOutput = output
        self.hapUsesDXTPath = useDXT
        return true
    }

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

    /// Human-readable label for the Hap variant carried in `track`'s
    /// first format description, suitable for logging. Returns `nil`
    /// for non-Hap tracks.
    private static func hapCodecLabel(for track: AVAssetTrack) -> String? {
        guard let desc = track.formatDescriptions.first else { return nil }
        let cmDesc = desc as! CMFormatDescription
        let sub = CMFormatDescriptionGetMediaSubType(cmDesc)
        let fourcc = String(
            unsafeUninitializedCapacity: 4,
            initializingUTF8With: { buf in
                buf[0] = UInt8((sub >> 24) & 0xFF)
                buf[1] = UInt8((sub >> 16) & 0xFF)
                buf[2] = UInt8((sub >> 8)  & 0xFF)
                buf[3] = UInt8( sub        & 0xFF)
                return 4
            }
        )
        let pretty: String
        switch sub {
        case hapCodec_Hap1:  pretty = "Hap"
        case hapCodec_Hap5:  pretty = "Hap Alpha"
        case hapCodec_Hap7:  pretty = "Hap 7"
        case 0x48617059:     pretty = "Hap Q"          // 'HapY'
        case 0x4861704D:     pretty = "Hap Q Alpha"    // 'HapM'
        case 0x48617048:     pretty = "Hap HDR"        // 'HapH'
        case 0x48617041:     pretty = "Hap Alpha-only" // 'HapA'
        default:             pretty = fourcc
        }
        return "\(pretty) [\(fourcc)]"
    }

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
    /// Textures come from `GraphRenderer.sharedTextureCache` — heap-
    /// backed, ring-recycled per-frame. BC formats are sampled-only,
    /// so we override the cache's default usage to `[.shaderRead]`;
    /// `.shared` storage is required because the upload is a CPU-side
    /// `replace(region:)` (illegal on `.private` on macOS).
    ///
    /// The texture is sized at the asset's true pixel dimensions
    /// (`frame.imgSize`), not the block-padded `frame.dxtImgSize`:
    /// for assets whose dimensions aren't a multiple of 4, the padded
    /// size would expose pad pixels along the right/bottom edges to
    /// any sampler reaching UV >= 1.0 - epsilon. The row stride passed
    /// to `replace(region:)` still comes from `dxtImgSize.width` —
    /// that's the stride the Hap decoder actually wrote — and Metal
    /// accepts a stride wider than `region.width` would imply, just
    /// skipping the unread tail bytes on each row.
    ///
    /// Edge case: BC1/BC3/BC7 textures themselves require dimensions
    /// that are multiples of 4 (one compressed block per 4×4 region).
    /// For sub-block-aligned `imgSize` we can't request a smaller
    /// texture — fall back to the padded `dxtImgSize` (the previous
    /// behaviour) and log once. Re-encoding the asset at a multiple-
    /// of-4 resolution is the user-visible fix.
    private func makeDXTImage(fromHapFrame frame: HapDecoderFrame, renderer: GraphRenderer) -> FabricImage? {
        // Hap Q Alpha is encoded as two planes (BC3 + RGTC1). The
        // single-plane Metal upload path here doesn't handle that;
        // those frames fall back via `outputAsRGB` at asset load.
        guard frame.dxtPlaneCount == 1 else { return nil }
        guard let mtlFormat = Self.metalFormat(forHapDXT: frame.dxtPixelFormats[0]) else { return nil }

        let dxtSize = frame.dxtImgSize
        let dxtWidth = Int(dxtSize.width)
        let dxtHeight = Int(dxtSize.height)
        let trueSize = frame.imgSize
        let trueWidth = Int(trueSize.width)
        let trueHeight = Int(trueSize.height)
        guard dxtWidth > 0, dxtHeight > 0, trueWidth > 0, trueHeight > 0 else { return nil }

        // BC1 / BC3 / BC7 require texture dimensions that are
        // multiples of 4. When the asset's true size doesn't satisfy
        // that, fall back to the padded `dxtImgSize` and log once per
        // asset — silently dropping the frame would leave the user
        // wondering why their odd-resolution Hap file plays black.
        let trueSizeIsBlockAligned = (trueWidth % 4 == 0) && (trueHeight % 4 == 0)
        let texWidth: Int
        let texHeight: Int
        if trueSizeIsBlockAligned
        {
            texWidth = trueWidth
            texHeight = trueHeight
        }
        else
        {
            if !self.didLogDXTSubBlockPadding
            {
                Self.log.notice("Hap DXT asset \"\(self.url?.lastPathComponent ?? "<nil>", privacy: .public)\" is \(trueWidth)×\(trueHeight) — not a multiple of 4. BC textures require block-aligned dimensions; falling back to padded \(dxtWidth)×\(dxtHeight). Re-encode at a multiple-of-4 resolution to drop the right/bottom padding pixels.")
                self.didLogDXTSubBlockPadding = true
            }
            texWidth = dxtWidth
            texHeight = dxtHeight
        }

        let dxtData = frame.dxtDatas[0]
        guard dxtData != nil else { return nil }

        guard let image = renderer.sharedTextureCache.newManagedImage(
            width: texWidth,
            height: texHeight,
            pixelFormat: mtlFormat,
            usage: [.shaderRead],
            mipmapped: false,
            label: "MovieProviderNode.HapDXT"
        ) else { return nil }

        // BC1 packs a 4×4 block in 8 bytes; BC3 / BC7 in 16 bytes.
        // Row stride is always derived from the padded width — that
        // is the stride the decoder wrote — even when the destination
        // texture is the smaller true-size.
        let blocksPerRow = (dxtWidth + 3) / 4
        let bytesPerBlock = (mtlFormat == .bc1_rgba) ? 8 : 16
        let bytesPerRow = blocksPerRow * bytesPerBlock

        let region = MTLRegionMake2D(0, 0, texWidth, texHeight)
        image.texture.replace(region: region, mipmapLevel: 0, withBytes: dxtData!, bytesPerRow: bytesPerRow)

        return image
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
}
