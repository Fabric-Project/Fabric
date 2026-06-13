//
//  AudioSpectrumNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/4/25.
//

import Foundation
import SwiftUI
import Satin
import simd
import AVFoundation
import Accelerate
import Dispatch
import Synchronization

public class AudioSpectrumNode : Node
{
    final class SimpleFilterBank {
        // ---- Config ----
        var sampleRate: Float
        var bandCount: Int
        var fMin: Float
        var fMax: Float
        var Q: Float = 4.3
        var dbFloor: Float = -80.0

        // Optional perceptual weighting
        var useAWeighting: Bool = true

        // ---- Envelope ----
        private var env = [Float]()
        var attackMS: Float = 10.0
        var releaseMS: Float = 10.0

        // ---- Per-band metadata/corrections ----
        private var gainCorrection  = [Float]()    // ≈ sqrt(Q / fc) to flatten low-end bias
        private var weightCorrection = [Float]()   // optional A-weighting (linear gain)

        // ---- vDSP biquad state ----
        // Coefficients are passed to vDSP_biquad_CreateSetup as doubles for precision.
        // vDSP_biquad uses Direct Form I; the Delay array holds [x[n-2], x[n-1], y[n-2], y[n-1]]
        // per band and is updated automatically by vDSP_biquad on each call.
        private var biquadSetups = [OpaquePointer?]()
        private var delays = [Float]()              // flat: bandCount × 4 elements

        // ---- Scratch buffers ----
        private var work        = [Float]()         // n samples: per-band filtered output
        private var rmsValues   = [Float]()         // bandCount
        private var correctedBuf = [Float]()        // bandCount
        private var dbBuf       = [Float]()         // bandCount
        private var normBuf     = [Float]()         // bandCount

        init(sampleRate: Float,
             bandCount: Int,
             fMin: Float = 50.0,
             fMax: Float = 12000.0,
             Q: Float = 4.3,
             dbFloor: Float = -80.0)
        {
            self.sampleRate = sampleRate
            self.bandCount  = max(1, bandCount)
            self.fMin = fMin
            self.fMax = fMax
            self.Q = Q
            self.dbFloor = dbFloor
            buildBands()
            env = .init(repeating: 0, count: self.bandCount)
        }

        deinit {
            for setup in biquadSetups { vDSP_biquad_DestroySetup(setup) }
        }

        // Call when bandCount / fMin / fMax / Q / sampleRate change.
        func buildBands() {
            // Tear down previous setups; the new filter starts from silence (delays = 0).
            for setup in biquadSetups { vDSP_biquad_DestroySetup(setup) }
            biquadSetups.removeAll(keepingCapacity: true)

            delays       = .init(repeating: 0, count: bandCount * 4)
            rmsValues    = .init(repeating: 0, count: bandCount)
            correctedBuf = .init(repeating: 0, count: bandCount)
            dbBuf        = .init(repeating: 0, count: bandCount)
            normBuf      = .init(repeating: 0, count: bandCount)

            gainCorrection   = .init(repeating: 1, count: bandCount)
            weightCorrection = .init(repeating: 1, count: bandCount)

            let r = fMax / fMin
            for k in 0..<bandCount {
                let t   = bandCount > 1 ? Float(k) / Float(bandCount - 1) : 0
                let fck = fMin * powf(r, t)

                let w0    = 2.0 * Float.pi * (fck / sampleRate)
                let cosw0 = cosf(w0)
                let sinw0 = sinf(w0)
                let alpha = sinw0 / (2.0 * Q)

                // RBJ band-pass (constant skirt gain), normalized by a0 = 1 + alpha
                let a0k  =  1.0 + alpha
                let b0k  =  alpha  / a0k
                let b1k  =  0.0   as Float
                let b2k  = -alpha  / a0k
                let a1k  = (-2.0 * cosw0) / a0k
                let a2k  = ( 1.0 - alpha) / a0k

                // vDSP_biquad_CreateSetup takes double coefficients for precision.
                var coeffs: [Double] = [Double(b0k), Double(b1k), Double(b2k),
                                        Double(a1k), Double(a2k)]
                biquadSetups.append(vDSP_biquad_CreateSetup(&coeffs, 1))

                // Bandwidth/energy tilt correction ~ sqrt(Q / fc)
                gainCorrection[k] = sqrtf(max(Q / max(fck, 1e-12), 0))

                if useAWeighting {
                    weightCorrection[k] = aWeightingLinear(fck)
                }
            }
        }

        // Rough A-weighting (linear gain). Inputs in Hz.
        private func aWeightingLinear(_ f: Float) -> Float {
            let f2 = max(f, 1e-3) * max(f, 1e-3)
            let f4 = f2 * f2
            let f12200:   Float = 12200.0
            let f12200_2: Float = f12200 * f12200
            let num = f4 * f12200_2
            // IEC 61672-1 / ISO 226
            let den = (f2 + 20.6*20.6) * sqrtf((f2 + 107.7*107.7) * (f2 + 737.9*737.9)) * (f2 + f12200_2)
            let a_dB = 20.0 * log10f(max(num / max(den, 1e-12), 1e-12)) + 2.0
            return powf(10.0, a_dB / 20.0)
        }

        // Returns [0,1] per band. Caller owns the UnsafeBufferPointer lifetime.
        func processAudioData(_ samples: UnsafeBufferPointer<Float>) -> ContiguousArray<Float> {
            let n = samples.count
            if work.count < n { work = .init(repeating: 0, count: n) }

            // Block-based envelope coefficients
            let hop = Float(n) / sampleRate
            let a   = 1 - expf(-hop / max(attackMS  * 0.001, 1e-6))
            let r   = 1 - expf(-hop / max(releaseMS * 0.001, 1e-6))

            // Pass 1: vDSP_biquad per band + RMS into rmsValues[]
            //
            // vDSP_biquad processes all N samples with SIMD, replacing the previous
            // scalar for-i loop. The Delay array [x[n-2], x[n-1], y[n-2], y[n-1]]
            // is updated in-place by vDSP_biquad and carries state across calls.
            work.withUnsafeMutableBufferPointer { workBuf in
                delays.withUnsafeMutableBufferPointer { delayBuf in
                    for k in 0..<bandCount {
                        guard let setup = biquadSetups[k] else { rmsValues[k] = 0; continue }
                        vDSP_biquad(setup,
                                    delayBuf.baseAddress!.advanced(by: k * 4),
                                    samples.baseAddress!, 1,
                                    workBuf.baseAddress!, 1,
                                    vDSP_Length(n))
                        vDSP_rmsqv(workBuf.baseAddress!, 1, &rmsValues[k], vDSP_Length(n))
                    }
                }
            }

            // Pass 2: vectorized corrections + dB normalization
            // Apply gain correction (bandwidth/energy tilt)
            vDSP_vmul(rmsValues, 1, gainCorrection, 1, &correctedBuf, 1, vDSP_Length(bandCount))
            if useAWeighting {
                vDSP_vmul(correctedBuf, 1, weightCorrection, 1, &correctedBuf, 1, vDSP_Length(bandCount))
            }
            // Floor before log to avoid log(0)
            var logFloor: Float = 1e-12
            var logCeil:  Float = .greatestFiniteMagnitude
            vDSP_vclip(correctedBuf, 1, &logFloor, &logCeil, &correctedBuf, 1, vDSP_Length(bandCount))
            // Vectorized log10, then × 20 → dB
            var n32 = Int32(bandCount)
            vvlog10f(&dbBuf, correctedBuf, &n32)
            var twenty: Float = 20.0
            vDSP_vsmul(dbBuf, 1, &twenty, &dbBuf, 1, vDSP_Length(bandCount))
            // Clamp to dbFloor
            vDSP_vthr(dbBuf, 1, &dbFloor, &dbBuf, 1, vDSP_Length(bandCount))
            // Normalize: (db - dbFloor) / (0 - dbFloor) = db * (1/(-dbFloor)) + 1
            var invNegDbFloor: Float = 1.0 / (-dbFloor)
            var one: Float = 1.0
            vDSP_vsmsa(dbBuf, 1, &invNegDbFloor, &one, &normBuf, 1, vDSP_Length(bandCount))
            // Clamp to [0, 1]
            var zero: Float = 0.0
            var oneClamp: Float = 1.0
            vDSP_vclip(normBuf, 1, &zero, &oneClamp, &normBuf, 1, vDSP_Length(bandCount))

            // Pass 3: envelope (sequential — each band depends only on its own prior state)
            var out = ContiguousArray<Float>(repeating: 0, count: bandCount)
            for k in 0..<bandCount {
                let norm  = normBuf[k]
                let ePrev = env[k].isFinite ? env[k] : 0
                var e = norm > ePrev ? ePrev + a * (norm - ePrev)
                                     : ePrev + r * (norm - ePrev)
                if !e.isFinite { e = 0 }
                env[k] = e
                out[k] = e
            }
            return out
        }
    }

    override public class var name:String { "Audio Spectrum" }
    override public class var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .Idle }
    override public class var nodeDescription: String { "Captures audio from the selected input device and emits a normalized per-band spectrum. Sensitivity controls how responsive the analyzer is to quiet sounds — 0 analyses only louder audio, 1 is full sensitivity. Gain multiplies the bar values after normalization, clamped to [0, 1] — a visual 'overdrive' that pushes bars toward full-scale without touching the underlying signal." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputAudioDevice", ParameterPort(parameter: StringParameter("Device Name", "", .dropdown, "Audio input device to capture from"))),
            ("inputBands", ParameterPort(parameter: IntParameter("Bands", 8, 1, 256, .inputfield, "Number of frequency bands in the spectrum output"))),
            ("inputSensitivity", ParameterPort(parameter: FloatParameter("Sensitivity", 0.5, 0.0, 1.0, .slider, "How sensitive the analyzer is to quiet sounds. 0 = analyses only louder sounds (quiet audio is ignored). 1 = full sensitivity (picks up even very faint audio). Turn up to make the display react to subtle input; turn down if you only care about peaks."))),
            ("inputGain", ParameterPort(parameter: FloatParameter("Gain", 1.0, 0.0, 10.0, .slider, "Multiplier applied to the output band values after normalization, clamped to [0, 1]. 1 = pass-through; values > 1 push bars toward full-scale ('visual overdrive' — the bars saturate earlier); values < 1 scale bars down. Purely affects the output, not the underlying audio analysis."))),
            ("inputSmoothing", ParameterPort(parameter: FloatParameter("Smoothing", 0.0, 0.0, 1.0, .slider, "Smoothing factor for frequency band transitions"))),
            ("inputAttack", ParameterPort(parameter: FloatParameter("Attack", 0.0, 0.0, 100.0, .slider, "Attack time in milliseconds for rising levels"))),
            ("inputRelease", ParameterPort(parameter: FloatParameter("Release", 0.0, 0.0, 100.0, .slider, "Release time in milliseconds for falling levels"))),
            ("outputSpectrum", NodePort<ContiguousArray<Float>>(name: "Spectrum", kind: .Outlet, description: "Array of frequency band values from 0 to 1")),
        ]
    }

    public var inputAudioDevice:ParameterPort<String> { port(named: "inputAudioDevice") }
    public var inputBands:ParameterPort<Int> { port(named: "inputBands") }
    public var inputSensitivity:ParameterPort<Float> { port(named: "inputSensitivity") }
    public var inputGain:ParameterPort<Float> { port(named: "inputGain") }
    public var inputSmoothing:ParameterPort<Float> { port(named: "inputSmoothing") }
    public var inputAttack:ParameterPort<Float> { port(named: "inputAttack") }
    public var inputRelease:ParameterPort<Float> { port(named: "inputRelease") }
    public var outputSpectrum:NodePort<ContiguousArray<Float>> { port(named: "outputSpectrum") }

    // Delegate receives CMSampleBuffers on the capture queue and forwards
    // them into the owner's captureState. Weak reference breaks the
    // otherwise self-retaining delegate/owner cycle.
    private final class CaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate
    {
        weak var owner: AudioSpectrumNode?

        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection)
        {
            self.owner?.processAudioSampleBuffer(sampleBuffer)
        }
    }

    // AVCaptureSession replaces AVAudioEngine: its per-session input device
    // selection via AVCaptureDeviceInput is the supported macOS API for
    // per-node device switching, where AVAudioEngine's AUHAL-routing is not.
    @ObservationIgnored private var captureSession = AVCaptureSession()
    @ObservationIgnored private let captureQueue   = DispatchQueue(label: "fabric.AudioSpectrumNode.capture_queue")
    @ObservationIgnored private var captureDelegate = CaptureDelegate()

    /// Capture-thread → consumer-thread handoff via a Mutex.
    ///
    /// The capture delegate (running on `captureQueue`) writes samples and the
    /// observed sample rate into `captureState` under the lock. `execute()` swaps
    /// the sample buffer out in one O(1) lock acquisition — no `captureQueue.sync`
    /// cross-queue blocking on the render thread. `captureQueue` is retained only
    /// as the AVCaptureSession delegate dispatch queue; it is no longer used as a
    /// synchronization primitive.
    private struct CaptureState {
        var samples:    [Float] = []
        var sampleRate: Float?  = nil
    }
    @ObservationIgnored private let captureState = Mutex<CaptureState>(CaptureState())

    // Device enumeration. AVCaptureDevice.DiscoverySession gives us the raw
    // AVCaptureDevice instances which feed straight into AVCaptureDeviceInput
    // — no UID→AudioDeviceID translation needed.
    @ObservationIgnored private let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
    )

    /// Available audio devices, populated from `AVCaptureDevice`
    /// connect/disconnect notifications.
    ///
    /// The observer is registered with `queue: .main` because the
    /// handler updates the dropdown's `StringParameter.options`, and
    /// Fabric's `@Observable` engine types (Node, Parameter, …) are
    /// main-thread-affine: Observation's change tracking misbehaves on
    /// non-main mutations. That's a property of Fabric's current
    /// parameter design — engine state and UI binding state share a
    /// single object — not a SwiftUI requirement of this node.
    ///
    /// `captureState` (a `Mutex`) is separate and is written from the
    /// capture queue and read from the consumer (execute) queue — no
    /// `.main` constraint applies there.
    private struct DeviceList: ~Copyable, @unchecked Sendable {
        var devices: [AVCaptureDevice] = []
    }
    @ObservationIgnored private let devicesLock = Mutex<DeviceList>(DeviceList())
    @ObservationIgnored private var wasConnectedObserver: Any?
    @ObservationIgnored private var wasDisconnectedObserver: Any?

    public required init(context: Context)
    {
        super.init(context: context)
        self.commonPostSetup()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.commonPostSetup()
    }

    deinit
    {
        if let t = wasConnectedObserver    { NotificationCenter.default.removeObserver(t) }
        if let t = wasDisconnectedObserver { NotificationCenter.default.removeObserver(t) }
    }

    private func commonPostSetup()
    {
        self.captureDelegate.owner = self
        self.refreshAudioDeviceOptions()

        self.wasConnectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAudioDeviceOptions()
        }
        self.wasDisconnectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAudioDeviceOptions()
        }
    }

    private func refreshAudioDeviceOptions()
    {
        let fresh = self.discoverySession.devices
        self.devicesLock.withLock { $0.devices = fresh }
        if let param = self.inputAudioDevice.parameter as? StringParameter
        {
            param.options = fresh.map(\.localizedName)
        }
    }

    private func resolveSelectedAudioDevice() -> AVCaptureDevice?
    {
        let knownDevices = self.devicesLock.withLock { $0.devices }
        if let name = self.inputAudioDevice.value, !name.isEmpty,
           let match = knownDevices.first(where: { $0.localizedName == name })
        {
            return match
        }
        return AVCaptureDevice.default(for: .audio)
    }

    override public func startExecution(renderer:GraphRenderer) {
        super.startExecution(renderer:renderer)

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                self.setupCaptureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    if granted {
                        print("Granted Mic Access")
                        self?.setupCaptureSession()
                    }
                    else
                    {
                        print("Not Granted Mic Access")
                    }
                }
            case .denied:
                print("Not Granted Mic Access")
            case .restricted:
                print("Restricted from Granting Mic Access")
            @unknown default:
                print("Restricted from Granting Mic Access")
        }
    }
    
    override public func stopExecution(renderer:GraphRenderer)
    {
        super.stopExecution(renderer:renderer)
        if self.captureSession.isRunning
        {
            self.captureSession.stopRunning()
        }
    }

    override public func disableExecution(renderer:GraphRenderer)
    {
        super.disableExecution(renderer:renderer)
        if self.captureSession.isRunning{
            self.captureSession.stopRunning()
        }
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputAudioDevice.valueDidChange
        {
            self.setupCaptureSession()
        }

        // Collect parameter changes; mark rebuild for structural params.
        // Attack/release are cheap live updates — no rebuild needed.
        var needsRebuild = filterBank == nil
        if self.inputSmoothing.valueDidChange, let v = self.inputSmoothing.value { smoothing = v; needsRebuild = true }
        if self.inputBands.valueDidChange,    let v = self.inputBands.value    { bands = v;    needsRebuild = true }
        if self.inputAttack.valueDidChange,   let v = self.inputAttack.value   { filterBank?.attackMS  = v }
        if self.inputRelease.valueDidChange,  let v = self.inputRelease.value  { filterBank?.releaseMS = v }

        // Single lock: swap the captured sample backlog + read observed rate.
        // The swap is O(1) (pointer exchange); the lock is held for nanoseconds.
        var capturedSamples: [Float] = []
        var capturedRate:    Float?  = nil
        captureState.withLock { state in
            swap(&capturedSamples, &state.samples)
            capturedRate = state.sampleRate
        }

        // Rebuild once with the best available rate — covers both structural
        // param changes and a first-seen rate change in the same tick.
        let activeRate = capturedRate ?? filterBank?.sampleRate ?? 48000
        if needsRebuild || (capturedRate != nil && capturedRate != filterBank?.sampleRate)
        {
            createFilterBank(sampleRate: activeRate, bandCount: bands, normalizedSmoothing: smoothing)
        }

        guard let filterBank, !capturedSamples.isEmpty else { return }

        let framesPerTick = Int(round(filterBank.sampleRate / 200))
        let batchCount    = min(framesPerTick, capturedSamples.count)

        // Sensitivity → filter-bank dbFloor. 0 = least sensitive (−30 dB floor);
        // 1 = most sensitive (−120 dB floor).
        let sensitivity = max(0, min(1, self.inputSensitivity.value ?? 0.5))
        filterBank.dbFloor = -30 - sensitivity * 90

        // Pass UnsafeBufferPointer sub-range — no copy.
        var output = capturedSamples.withUnsafeBufferPointer { ptr in
            filterBank.processAudioData(UnsafeBufferPointer(start: ptr.baseAddress!, count: batchCount))
        }

        // Apply gain + clamp in-place with vDSP — no extra allocation.
        var gain = self.inputGain.value ?? 1.0
        var zero: Float = 0, one: Float = 1
        output.withUnsafeMutableBufferPointer { buf in
            vDSP_vsmul(buf.baseAddress!, 1, &gain, buf.baseAddress!, 1, vDSP_Length(buf.count))
            vDSP_vclip(buf.baseAddress!, 1, &zero, &one, buf.baseAddress!, 1, vDSP_Length(buf.count))
        }

        self.outputSpectrum.send(output)

        if self.showSettings
        {
            self.visualizationBandValues = Array(output)
        }
    }

    var filterBank: SimpleFilterBank? = nil

    let maxSamples = 4096

    private var bands:    Int   = 8
    private var smoothing: Float = 0.0

    func createFilterBank(sampleRate: Float, bandCount: Int, normalizedSmoothing: Float)
    {
        // Guard sampleRate (CoreAudio-sourced, not from a port) and the Q
        // derived from remap — a zero Q produces NaN biquad coefficients.
        let safeRate: Float = (sampleRate.isFinite && sampleRate > 0) ? sampleRate : 48000
        let safeBands = max(1, bandCount)

        let q = remap(normalizedSmoothing, 1.0, 0.0, 0.0, Float(safeBands))
        let safeQ: Float = (q.isFinite && q > 0) ? q : Float(safeBands)

        self.filterBank = SimpleFilterBank(sampleRate: safeRate,
                                           bandCount: safeBands,
                                           fMin: 20.0,
                                           fMax: 15_000.0,
                                           Q: safeQ,
                                           dbFloor: -120.0)

        self.filterBank?.attackMS  = self.inputAttack.value  ?? 10.0
        self.filterBank?.releaseMS = self.inputRelease.value ?? 10.0
    }

    /// Called on the capture queue for every audio sample buffer. Appends
    /// Float32 samples directly into `captureState` — no intermediate copy.
    fileprivate func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        let asbd = asbdPtr.pointee
        let sampleRate    = Float(asbd.mSampleRate)
        let channels      = max(1, Int(asbd.mChannelsPerFrame))
        let isFloat       = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)

        // AVCaptureAudioDataOutput on macOS delivers Float32 LPCM by default.
        // Skip anything else — better silent drop than garbage into the filter bank.
        guard isFloat, bitsPerChannel == 32 else { return }

        var blockBuffer: CMBlockBuffer?
        var abl = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(&abl)
        guard let firstBuffer = buffers.first, let dataPtr = firstBuffer.mData else { return }

        let stride     = isInterleaved ? channels : 1
        let frameCount = Int(firstBuffer.mDataByteSize) / (stride * MemoryLayout<Float>.size)
        let floats     = dataPtr.assumingMemoryBound(to: Float.self)

        // Append directly into captureState — eliminates the previous
        // intermediate [Float] allocation and the separate append call.
        captureState.withLock { state in
            if sampleRate.isFinite, sampleRate > 0 { state.sampleRate = sampleRate }
            state.samples.reserveCapacity(state.samples.count + frameCount)
            for i in 0..<frameCount {
                let s = floats[i * stride]
                state.samples.append(s.isFinite ? s : 0)
            }
        }
    }

    /// Build (or rebuild) the capture session for the currently-selected device.
    ///
    /// Recreates AVCaptureSession itself on each call rather than reconfiguring
    /// in-place. Some virtual devices (e.g. Rogue Amoeba Loopback) deliver
    /// streams whose format the existing session's CMIO converter can't
    /// re-negotiate mid-session (`AudioConverterSetProperty(dbca) = pcm!`).
    /// A fresh session forces a fresh converter.
    private func setupCaptureSession()
    {
        guard let device = self.resolveSelectedAudioDevice() else
        {
            print("AudioSpectrum: no audio input device available")
            return
        }

        if self.captureSession.isRunning { self.captureSession.stopRunning() }

        let session = AVCaptureSession()
        session.beginConfiguration()

        do
        {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else
            {
                print("AudioSpectrum: cannot add input for device \(device.localizedName)")
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            // Pin the output format so CMIO has an unambiguous target.
            // Matches what processAudioSampleBuffer() extracts.
            output.audioSettings = [
                AVFormatIDKey:               kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey:      32,
                AVLinearPCMIsFloatKey:       true,
                AVLinearPCMIsBigEndianKey:   false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey:             48_000.0,
                AVNumberOfChannelsKey:       1
            ]
            output.setSampleBufferDelegate(self.captureDelegate, queue: self.captureQueue)
            guard session.canAddOutput(output) else
            {
                print("AudioSpectrum: cannot add audio output")
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
        }
        catch
        {
            print("AudioSpectrum: failed to create capture input:", error)
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()

        self.captureSession = session
        self.captureSession.startRunning()

        // Flush stale samples so the first buffer from the new device drives
        // the filter-bank rebuild, not leftover data from the old device.
        captureState.withLock { state in
            state.samples.removeAll(keepingCapacity: true)
            state.sampleRate = nil
        }
    }

    // MARK: - Visualization

    // Consumed by the settings popover; populated in execute() only while
    // showSettings is true.
    @ObservationIgnored public var visualizationBandValues: [Float] = []

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        AnyView(AudioSpectrumNodeSettingsView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 460, height: 180)) }
}

// MARK: - Settings View

private struct AudioSpectrumNodeSettingsView: View
{
    @Bindable var node: AudioSpectrumNode

    var body: some View
    {
        BandsVisualizer(bands: { node.visualizationBandValues })
    }
}
