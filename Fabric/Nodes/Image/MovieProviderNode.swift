//
//  MovieProviderNode.swift
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
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Current video frame")),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var inputPlayingParam:ParameterPort<Bool>     { port(named: "inputPlayingParam") }
    public var inputSeekTimeParam:ParameterPort<Float>   { port(named: "inputSeekTimeParam") }
    public var outputTexturePort:NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var url: URL? = nil
    @ObservationIgnored private var asset:AVURLAsset? = nil
    @ObservationIgnored private var player:AVPlayer = AVPlayer()
    @ObservationIgnored private var playerItemVideoOutput:AVPlayerItemVideoOutput

    /// Async task spawned by `loadAssetFromInputValue` to do the
    /// track-load + AVPlayerItemHapMetalOutput construction off the
    /// execute queue. Cancelled at the start of the next load to drop
    /// any in-flight stale work. Anything past the Task's last
    /// cancellation checkpoint that still writes to `pendingLock` is
    /// caught by the URL-identity guard at drain time.
    @ObservationIgnored private var assetLoadTask: Task<Void, Never>? = nil

    /// Drives the seek-to-zero+play loop at end-of-asset. Iterates
    /// `NotificationCenter.default.notifications(named:object:)` for
    /// `AVPlayerItem.didPlayToEndTimeNotification` against the current
    /// player item. Cancelled at every asset swap; replaced by a new
    /// Task targeting the new player item.
    ///
    /// Replaces the previous `observer: Any?` + addObserver-with-queue
    /// pattern — that variant baked in a `.main` queue assumption
    /// (rejected: Fabric may run off main) and was awkwardly
    /// cancellable. The async-sequence Task is naturally cancellable,
    /// imposes no thread assumptions (AVPlayer.seek/.play are
    /// thread-safe), and collapses observer + cleanup into a single
    /// field.
    @ObservationIgnored private var loopTask: Task<Void, Never>? = nil

    /// Slot for the assembled `AVPlayerItem` + outputs, written from
    /// the load task, drained at the top of the next `execute()` tick.
    /// The lock is the single cross-queue handoff — everything else
    /// runs on the execute queue and stays lock-free.
    private let pendingLock = OSAllocatedUnfairLock<PendingAttachment?>(uncheckedState: nil)

    /// Video track's natural timescale, captured at load time from the
    /// async-loaded track. Used by `performSeek` so seeks land on
    /// sample boundaries without needing the deprecated synchronous
    /// `tracks(withMediaType:)` accessor at seek time.
    @ObservationIgnored private var videoNaturalTimeScale: CMTimeScale = 600

#if FABRIC_HAP_ENABLED
    /// High-level Hap output, attached to the current player item when
    /// the asset has a Hap video track. `nil` otherwise (including the
    /// "load in flight" window). The framework auto-attaches the
    /// underlying `AVPlayerItemHapDXTOutput` during its async init;
    /// `remove(from:)` detaches it at the next asset swap.
    @ObservationIgnored private var hapMetalOutput: AVPlayerItemHapMetalOutput? = nil
#endif

    /// Result of an async asset load, handed from the load task to
    /// `execute()` via `pendingLock`. Once drained, all fields are
    /// applied to live node state on the execute queue.
    fileprivate struct PendingAttachment {
        let url: URL
        let playerItem: AVPlayerItem
        let videoNaturalTimeScale: CMTimeScale
        let durationSeconds: TimeInterval
#if FABRIC_HAP_ENABLED
        /// `nil` when the asset has no Hap video tracks — the standard
        /// `playerItemVideoOutput` is attached to `playerItem` in that
        /// case instead.
        let hapMetalOutput: AVPlayerItemHapMetalOutput?
#endif
    }

    /// Asset duration in seconds. Captured async at load time via
    /// `try await asset.load(.duration)` — no deprecated synchronous
    /// `asset.duration` accessor. Returns 0 before the load completes
    /// and for assets whose duration is infinite (live streams).
    public var duration: TimeInterval { self.cachedDurationSeconds }

    @ObservationIgnored private var cachedDurationSeconds: TimeInterval = 0

    /// Player's current playback time in seconds.
    public var currentTime: TimeInterval {
        let cmTime = self.player.currentTime()
        let seconds = CMTimeGetSeconds(cmTime)
        return seconds.isFinite ? seconds : 0
    }

    /// Whether a seek is in flight. Used internally by `performSeek`
    /// to coalesce concurrent seek requests (see `pendingSeekTarget`)
    /// and by `execute()` to know when to drain that pending target.
    ///
    /// `@ObservationIgnored` because the seek completion handler
    /// fires on an internal AVPlayer queue, off-main. Fabric's
    /// `@Observable` engine types are main-thread-affine — without
    /// the opt-out, the off-main write would be Observation UB.
    @ObservationIgnored private var seeking: Bool = false

    /// Set by `performSeek`'s completion handler when the player is
    /// paused at seek-land time, cleared after the next `execute()`
    /// emit attempt. AVPlayerItemVideoOutput stops emitting fresh
    /// pixel buffers while the player is paused, so without this
    /// one-shot the seeked-to frame would never reach downstream
    /// consumers until playback resumed.
    ///
    /// Threading note as per `seeking` — written from AVFoundation's
    /// internal queue, so `@ObservationIgnored`.
    @ObservationIgnored private var needsEmitAfterSeek: Bool = false

    /// Coalesce-buffer for seek targets arriving while a previous seek
    /// is still in flight. Written from `performSeek` on the consumer
    /// queue; drained from `execute()` once `seeking` clears. Only the
    /// latest value survives — intermediate targets are dropped, which
    /// is the point: a seek-storm of nearby targets resolves to one
    /// final seek to the latest, not N cancelled+restarted seeks.
    @ObservationIgnored private var pendingSeekTarget: TimeInterval? = nil

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
        // Use the timescale captured at load time so seeks land on
        // sample boundaries without reaching for the deprecated sync
        // `tracks(withMediaType:)` accessor each time.
        let target = CMTime(seconds: clamped, preferredTimescale: self.videoNaturalTimeScale)
        let tol: CMTime = self.seekTolerance.isInfinite
            ? .positiveInfinity
            : CMTime(seconds: self.seekTolerance, preferredTimescale: self.videoNaturalTimeScale)
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
        // Drain any completed async load from a previous tick. Must
        // happen before the load kick-off below — otherwise a load
        // queued this tick would clobber a result delivered between
        // the last tick and this one.
        self.drainPendingAttachment()

        if self.inputFilePathParam.valueDidChange
        {
            loadAssetFromInputValue(renderer: renderer)
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

    /// Async-load kick-off. Runs on the execute queue: tears down the
    /// previous attachment, then spawns a Task that loads tracks,
    /// constructs the Hap framework's high-level output (or detects
    /// "no Hap track"), and parks an assembled `PendingAttachment` in
    /// `pendingLock`. The next `execute()` tick drains and applies it.
    ///
    /// Stale-load defense: `assetLoadTask?.cancel()` cooperatively
    /// stops in-flight work; anything past the last cancellation
    /// checkpoint that still writes to `pendingLock` is filtered out
    /// at drain time by the URL-identity check.
    private func loadAssetFromInputValue(renderer: GraphRenderer)
    {
        guard let path = self.inputFilePathParam.value,
              !path.isEmpty, self.url != URL(string: path)
        else { return }
        self.url = URL(string: path)

        guard let url,
              FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false))
        else {
            self.outputTexturePort.send( nil )
            Self.log.error("Movie file not found at \(self.url?.path() ?? "<nil>", privacy: .public)")
            return
        }

        // Cancel any in-flight load and the end-of-asset loop — both
        // were targeting the previous URL.
        self.assetLoadTask?.cancel()
        self.assetLoadTask = nil
        self.loopTask?.cancel()
        self.loopTask = nil

        // Discard any pending attachment that hasn't been drained yet
        // — also for a previous URL.
        _ = self.pendingLock.withLock { state -> PendingAttachment? in
            let p = state; state = nil; return p
        }

        // Tear down current playback synchronously. The intentional
        // blank gap until the new asset's tracks load is preferable
        // to keeping the previous asset visible on the output port
        // after the user changed paths.
        self.player.pause()
        self.cachedDurationSeconds = 0
#if FABRIC_HAP_ENABLED
        if let oldMetal = self.hapMetalOutput, let oldItem = self.player.currentItem {
            oldMetal.remove(from: oldItem)
        }
        self.hapMetalOutput = nil
#endif
        if let oldItem = self.player.currentItem
        {
            oldItem.remove(self.playerItemVideoOutput)
        }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.asset = asset

        // Capture renderer-owned resources for the Task explicitly.
        // `sharedTextureCache` is captured via the Sendable
        // FabricHapAllocator wrapper. The standard `playerItemVideoOutput`
        // is captured directly — only attached to the player item on
        // the .noHapTrack branch.
#if FABRIC_HAP_ENABLED
        let textureAllocator = FabricHapAllocator(cache: renderer.sharedTextureCache)
#endif
        let videoOutput = self.playerItemVideoOutput

#if FABRIC_HAP_ENABLED
        self.assetLoadTask = Task { [weak self, url, asset, textureAllocator, videoOutput] in
            do {
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 0.5

                // Capture the video track's natural timescale up-front
                // so seeks can build sample-accurate CMTimes without
                // reaching for the deprecated synchronous accessor.
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let timescale: CMTimeScale
                do {
                    timescale = (try await videoTracks.first?.load(.naturalTimeScale)) ?? 600
                } catch is CancellationError {
                    return
                } catch {
                    timescale = 600
                }

                try Task.checkCancellation()

                // Capture the asset's duration alongside the timescale
                // so the public `duration` getter doesn't need to reach
                // for the deprecated synchronous `asset.duration`
                // accessor. Infinite (live-stream) durations clamp to 0.
                let durationSeconds: TimeInterval
                do {
                    let cm = try await asset.load(.duration)
                    let s = CMTimeGetSeconds(cm)
                    durationSeconds = s.isFinite ? max(0, s) : 0
                } catch is CancellationError {
                    return
                } catch {
                    durationSeconds = 0
                }

                try Task.checkCancellation()

                // Auto-attaches the underlying AVPlayerItemHapDXTOutput
                // to playerItem when the asset has a Hap track. If
                // mode == .noHapTrack we add the standard video output
                // below.
                let metalOutput = try await AVPlayerItemHapMetalOutput(
                    playerItem: playerItem,
                    textureAllocator: textureAllocator)

                try Task.checkCancellation()

                // The framework is built BUILD_LIBRARY_FOR_DISTRIBUTION,
                // so its public enums are treated as having potentially
                // unknown future cases — `@unknown default` keeps the
                // switch source-compatible if a new Mode case lands.
                switch metalOutput.mode {
                case .dxtDirect(let codec):
                    print("MovieProviderNode: Hap DXT direct upload path engaged for \"\(url.lastPathComponent)\" (codec \(codec.displayName))")
                case .rgbFallback(let codec):
                    Self.log.notice("Hap RGB fallback path engaged for \"\(url.lastPathComponent, privacy: .public)\" (codec \(codec.displayName, privacy: .public)). Re-encode as Hap, Hap Alpha, or Hap 7 for the DXT direct-upload fast path.")
                case .noHapTrack:
                    playerItem.add(videoOutput)
                    print("MovieProviderNode: AVPlayerItemVideoOutput path engaged for \"\(url.lastPathComponent)\"")
                @unknown default:
                    playerItem.add(videoOutput)
                    Self.log.error("Unknown AVPlayerItemHapMetalOutput.Mode for \(url.lastPathComponent, privacy: .public); falling back to standard AVPlayerItemVideoOutput")
                }

                let pending = PendingAttachment(
                    url: url,
                    playerItem: playerItem,
                    videoNaturalTimeScale: timescale,
                    durationSeconds: durationSeconds,
                    hapMetalOutput: metalOutput.mode == .noHapTrack ? nil : metalOutput
                )
                self?.pendingLock.withLock { $0 = pending }
            } catch is CancellationError {
                return
            } catch {
                Self.log.error("Failed to set up player item for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
#else
        self.assetLoadTask = Task { [weak self, url, asset, videoOutput] in
            do {
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 0.5

                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let timescale: CMTimeScale
                do {
                    timescale = (try await videoTracks.first?.load(.naturalTimeScale)) ?? 600
                } catch is CancellationError {
                    return
                } catch {
                    timescale = 600
                }

                try Task.checkCancellation()

                // Capture the asset's duration alongside the timescale
                // so the public `duration` getter doesn't need to reach
                // for the deprecated synchronous `asset.duration`
                // accessor. Infinite (live-stream) durations clamp to 0.
                let durationSeconds: TimeInterval
                do {
                    let cm = try await asset.load(.duration)
                    let s = CMTimeGetSeconds(cm)
                    durationSeconds = s.isFinite ? max(0, s) : 0
                } catch is CancellationError {
                    return
                } catch {
                    durationSeconds = 0
                }

                try Task.checkCancellation()
                playerItem.add(videoOutput)
                print("MovieProviderNode: AVPlayerItemVideoOutput path engaged for \"\(url.lastPathComponent)\"")

                let pending = PendingAttachment(
                    url: url,
                    playerItem: playerItem,
                    videoNaturalTimeScale: timescale,
                    durationSeconds: durationSeconds
                )
                self?.pendingLock.withLock { $0 = pending }
            } catch is CancellationError {
                return
            } catch {
                Self.log.error("Failed to set up player item for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
#endif
    }

    /// Drain a pending attachment delivered by `assetLoadTask`. Runs
    /// on the execute queue at the top of every `execute()` tick.
    ///
    /// The URL-identity guard handles the "stale Task wrote pending
    /// after we cancelled it but before its last cancellation point"
    /// race: by the time we drain, `self.url` has already moved on,
    /// so the stale pending is silently dropped.
    private func drainPendingAttachment()
    {
        let pending = pendingLock.withLock { state -> PendingAttachment? in
            let p = state; state = nil; return p
        }
        guard let pending, pending.url == self.url else { return }

        // Wire end-of-asset → seek-to-zero+play loop. Iterating the
        // async notification sequence inside a Task gives us
        // cancellation for free and avoids the `.main` queue
        // assumption the old addObserver path baked in.
        self.loopTask?.cancel()
        // Both captures are weak so the loop doesn't outlive its
        // referents. `self` is the obvious one; the player item is
        // strongly held by the AVPlayer via `replaceCurrentItem`, so
        // weak here just means the Task drops out if `self` (and
        // therefore the player) is gone.
        self.loopTask = Task { [weak self, weak item = pending.playerItem] in
            guard let item else { return }
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            {
                guard let self else { return }
                // AVPlayer.seek/.play are thread-safe; no need to hop.
                // Use the completion-handler overload so Swift picks
                // the sync (fire-and-forget) variant, not the async one.
                self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero,
                                 completionHandler: { _ in })
                self.player.play()
            }
        }

#if FABRIC_HAP_ENABLED
        self.hapMetalOutput = pending.hapMetalOutput
#endif
        self.videoNaturalTimeScale = pending.videoNaturalTimeScale
        self.cachedDurationSeconds = pending.durationSeconds

        self.player.replaceCurrentItem(with: pending.playerItem)
        self.player.volume = 0.0
        self.player.actionAtItemEnd = .none
        if (self.inputPlayingParam.value ?? true) { self.player.play() }
        else { self.player.pause() }
    }

#if FABRIC_HAP_ENABLED
    /// Emit the current Hap frame when a Hap output is attached.
    /// Returns `true` when the Hap path "owns" this tick (caller skips
    /// the standard AVPlayerItemVideoOutput branch), `false` when no
    /// Hap output is attached — the asset uses the standard pipeline
    /// in that case (e.g. .noHapTrack assets where loadAsset attached
    /// the standard video output instead; `hapMetalOutput` is left nil
    /// in that case).
    ///
    /// All the Hap-specific work (codec detection, DXT direct upload,
    /// RGB fallback, PTS dedupe, BC alignment fallback) lives in
    /// `AVPlayerItemHapMetalOutput` upstream — this method is just
    /// the per-tick ask: "give me the next texture if you've got one."
    /// A `nil` return means no new frame yet (decoder warming up, or
    /// dedupe filtered a same-PTS frame); the Hap path still "owns"
    /// the tick either way, so we return `true` without falling
    /// through to the standard pipeline.
    ///
    /// Note: `needsEmitAfterSeek` is set by `performSeek`'s completion
    /// handler for both paths but is only consumed by the standard
    /// pipeline below. The two paths diverge on paused-seek-to-same-
    /// frame: the AVF branch re-emits the same buffer (harmless
    /// redundant downstream tick); the Hap branch skips, because the
    /// framework's internal dedupe gates on PTS. This asymmetry
    /// mirrors the underlying API shapes — `AVPlayerItemHapDXTOutput`
    /// has no `hasNewFrame`-style gate, so dedupe lives in the
    /// framework; `AVPlayerItemVideoOutput` has `hasNewPixelBuffer`,
    /// and trusting it keeps the AVF branch short.
    private func executeHapPath(renderer: GraphRenderer, hostTime: CFTimeInterval) -> Bool
    {
        guard let output = self.hapMetalOutput else { return false }

        let itemTime = output.itemTime(forHostTime: hostTime)
        guard let managed = output.newTexture(forItemTime: itemTime)
        else { return true }

        // `FabricImage` conforms to `HapManagedTexture` via our
        // adapter, and `FabricHapAllocator` always returns a
        // `FabricImage`. Force-cast makes the invariant a runtime
        // assertion — a future allocator change that breaks it
        // surfaces immediately rather than going through a silently-
        // less-efficient wrapping fallback.
        let image: FabricImage = managed as! FabricImage
        self.outputTexturePort.send(image)
        return true
    }
#endif
}

#if FABRIC_HAP_ENABLED
// MARK: - Hap framework adapters

/// `FabricImage` already wraps an `MTLTexture` plus a release closure
/// pointing at the originating `GraphRendererTextureCache` slot —
/// exactly the "managed texture handed to the caller" contract the
/// Hap framework's `HapManagedTexture` protocol asks for. Adding the
/// conformance lets the allocator return `FabricImage` instances
/// directly, no extra wrapper layer needed.
///
/// Conditional on `FABRIC_HAP_ENABLED` because `HapManagedTexture`
/// only exists when the Hap module is linked.
extension FabricImage: HapManagedTexture {}

/// Bridges Fabric's `GraphRendererTextureCache` to the Hap framework's
/// allocator protocol. Used for both DXT-direct (BC1/BC3/BC7) and RGB
/// fallback (.bgra8Unorm) paths — `GraphRendererTextureCache` handles
/// both pixel formats out of the same heap-backed pool with `.shared`
/// storage and `.shaderRead` usage.
///
/// `@unchecked Sendable`: the only stored state is an immutable
/// `let` reference to `GraphRendererTextureCache`, whose own
/// concurrency model is independent of this wrapper. Marking it
/// `Sendable` lets us capture the allocator into the load Task
/// without a Swift 6 strict-concurrency warning.
final class FabricHapAllocator: HapTextureAllocator, @unchecked Sendable {
    let cache: GraphRendererTextureCache
    init(cache: GraphRendererTextureCache) { self.cache = cache }

    func makeTexture(width: Int,
                     height: Int,
                     pixelFormat: MTLPixelFormat) -> (any HapManagedTexture)? {
        return cache.newManagedImage(width: width,
                                     height: height,
                                     pixelFormat: pixelFormat,
                                     usage: [.shaderRead],
                                     mipmapped: false,
                                     label: "Hap")
    }
}
#endif
