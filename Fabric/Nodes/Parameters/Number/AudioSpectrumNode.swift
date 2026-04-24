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

        // ---- Coeffs/state per band ----
        private var b0 = [Float](), b1 = [Float](), b2 = [Float](), a1 = [Float](), a2 = [Float]()
        private var z1 = [Float](), z2 = [Float]()

        // ---- New: per-band metadata/corrections ----
        private var fc = [Float]()                 // center frequency per band
        private var gainCorrection = [Float]()     // ≈ sqrt(Q / fc) to flatten low-end bias
        private var weightCorrection = [Float]()   // optional A-weighting (linear gain)

        // ---- Envelope ----
        private var env = [Float]()
        var attackMS: Float = 10.0
        var releaseMS: Float = 10.0

        // ---- Scratch ----
        private var work = [Float]()

        init(sampleRate: Float,
             bandCount: Int,
             fMin: Float = 50.0,
             fMax: Float = 12000.0,
             Q: Float = 4.3,
             dbFloor: Float = -80.0)
        {
            self.sampleRate = Float(sampleRate)
            self.bandCount  = max(1, bandCount)
            self.fMin = fMin
            self.fMax = fMax
            self.Q = Q
            self.dbFloor = dbFloor
            buildBands()
            env = .init(repeating: 0, count: bandCount)
        }

        // Call if bandCount / fMin / fMax / Q / sampleRate change
        func buildBands() {
            b0 = .init(repeating: 0, count: bandCount)
            b1 = .init(repeating: 0, count: bandCount)
            b2 = .init(repeating: 0, count: bandCount)
            a1 = .init(repeating: 0, count: bandCount)
            a2 = .init(repeating: 0, count: bandCount)
            z1 = .init(repeating: 0, count: bandCount)
            z2 = .init(repeating: 0, count: bandCount)

            fc = .init(repeating: 0, count: bandCount)
            gainCorrection = .init(repeating: 1, count: bandCount)
            weightCorrection = .init(repeating: 1, count: bandCount)

            // Log-spaced centers
            let r = fMax / fMin
            for k in 0..<bandCount {
                let t  = bandCount > 1 ? Float(k) / Float(bandCount - 1) : 0
                let fck = fMin * powf(r, t)
                fc[k] = fck

                let w0 = 2.0 * .pi * (fck / sampleRate)
                let cosw0 = cosf(w0)
                let sinw0 = sinf(w0)
                let alpha = sinw0 / (2.0 * Q)

                // RBJ band-pass (constant skirt gain)
                var b0k:Float =  alpha
                var b1k:Float =  0.0
                var b2k:Float = -alpha
                let a0k:Float =  1.0 + alpha
                var a1k:Float = -2.0 * cosw0
                var a2k:Float =  1.0 - alpha

                // Normalize
                b0k /= a0k; b1k /= a0k; b2k /= a0k
                a1k /= a0k; a2k /= a0k

                b0[k] = b0k; b1[k] = b1k; b2[k] = b2k
                a1[k] = a1k; a2[k] = a2k

                // --- Corrections ---
                // 1) Bandwidth/energy tilt ~ sqrt(Q / fc)
                gainCorrection[k] = sqrtf(max(Q / max(fck, 1e-12), 0))

                // 2) Optional A-weighting (linear gain)
                if useAWeighting {
                    weightCorrection[k] = aWeightingLinear(fck)
                }
            }
        }

        // Rough A-weighting (linear gain). Inputs in Hz.
        private func aWeightingLinear(_ f: Float) -> Float {
            // Guard very low frequencies
            let f2 = max(f, 1e-3) * max(f, 1e-3)
            let f4 = f2 * f2
            let f12200 = 12200.0 as Float
            let f12200_2 = f12200 * f12200
            let num = f4 * f12200_2
            
            // IEC 61672-1 / ISO 226 formulation for the A-weighting curve
            let den = (f2 + 20.6*20.6) * sqrtf((f2 + 107.7*107.7) * (f2 + 737.9*737.9)) * (f2 + f12200_2)
            // +2 dB offset to align with common implementations;
            let a_dB = 20.0 * log10f(max(num / max(den, 1e-12), 1e-12)) + 2.0
            return powf(10.0, a_dB / 20.0)
        }

        // Main entry: returns [0,1] per band
        func processAudioData<C: RandomAccessCollection>(samples:C) -> ContiguousArray<Float> where C.Element == Float, C.Index == Int  {

            let n = samples.count
            if work.count < n { work = .init(repeating: 0, count: n) }

            // Block-based envelope coefficients
            let hop = Float(n) / sampleRate
            let a = 1 - expf(-hop / max(attackMS * 0.001, 1e-6))
            let r = 1 - expf(-hop / max(releaseMS * 0.001, 1e-6))

            var out = ContiguousArray<Float>(repeating: 0, count: bandCount)

            for k in 0..<bandCount {
                // --- filter ---
                var zz1 = z1[k], zz2 = z2[k]
                let b0k = b0[k], b1k = b1[k], b2k = b2[k], a1k = a1[k], a2k = a2[k]
                for i in 0..<n {
                    let x = samples[i]
                    let y = b0k * x + zz1
                    zz1 = b1k * x - a1k * y + zz2
                    zz2 = b2k * x - a2k * y
                    work[i] = y
                }
                z1[k] = zz1; z2[k] = zz2

                // --- RMS ---
                var rms: Float = 0
                vDSP_rmsqv(work, 1, &rms, vDSP_Length(n))

                // --- Apply corrections BEFORE dB ---
                let corrected = rms * gainCorrection[k] * (useAWeighting ? weightCorrection[k] : 1.0)

                // --- dB -> [0,1] ---
                var db = 20.0 * log10f(max(corrected, 1e-12))
                if db < dbFloor { db = dbFloor }
                let norm = min(max((db - dbFloor) / (0 - dbFloor), 0), 1)

                // --- envelope ---
                // Self-heal: if env[k] got NaN/Inf (e.g. from a bad biquad
                // transient) it would otherwise stick forever because
                // `env + r * (x - env)` with a NaN env is always NaN.
                let ePrev = env[k].isFinite ? env[k] : 0
                var e = (norm > ePrev) ? (ePrev + a * (norm - ePrev))
                                       : (ePrev + r * (norm - ePrev))
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
    override public class var nodeDescription: String { "Provides Audio Spectrum Data as Number Array"}
        
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputAudioDevice", ParameterPort(parameter: StringParameter("Device Name", "", .dropdown, "Audio input device to capture from"))),
            ("inputGain", ParameterPort(parameter: FloatParameter("Gain", 1.0, 0.0, 4.0, .slider, "Linear gain applied to input samples before spectral analysis"))),
            ("inputBands", ParameterPort(parameter: IntParameter("Bands", 8, 1, 256, .inputfield, "Number of frequency bands in the spectrum output"))),
            ("inputSmoothing", ParameterPort(parameter: FloatParameter("Smoothing", 0.0, 0.0, 1.0, .slider, "Smoothing factor for frequency band transitions"))),
            ("inputAttack", ParameterPort(parameter: FloatParameter("Attack", 0.0, 0.0, 100.0, .slider, "Attack time in milliseconds for rising levels"))),
            ("inputRelease", ParameterPort(parameter: FloatParameter("Release", 0.0, 0.0, 100.0, .slider, "Release time in milliseconds for falling levels"))),
            ("outputSpectrum", NodePort<ContiguousArray<Float>>(name: "Spectrum", kind: .Outlet, description: "Array of frequency band values from 0 to 1")),
        ]
    }
    
    public var inputAudioDevice:ParameterPort<String> { port(named: "inputAudioDevice") }
    public var inputGain:ParameterPort<Float> { port(named: "inputGain") }
    public var inputBands:ParameterPort<Int> { port(named: "inputBands") }
    public var inputSmoothing:ParameterPort<Float> { port(named: "inputSmoothing") }
    public var inputAttack:ParameterPort<Float> { port(named: "inputAttack") }
    public var inputRelease:ParameterPort<Float> { port(named: "inputRelease") }
    public var outputSpectrum:NodePort<ContiguousArray<Float>> { port(named: "outputSpectrum") }

    // Delegate receives CMSampleBuffers on the capture queue and forwards
    // them into the owner's filter-bank sample queue. Weak reference breaks
    // the otherwise self-retaining delegate/owner cycle.
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
    @ObservationIgnored private let captureQueue = DispatchQueue(label: "net.sparklive.AudioSpectrum.capture")
    @ObservationIgnored private var captureDelegate = CaptureDelegate()

    // GraphRenderer only calls startExecution once, at renderer setup. Nodes
    // dropped onto an already-running graph never receive it, so we also
    // attempt setup lazily from execute() (see requestAudioSetupIfNeeded()).
    @ObservationIgnored private var didRequestAudioSetup = false

    // Device enumeration. AVCaptureDevice.DiscoverySession gives us the raw
    // AVCaptureDevice instances which feed straight into AVCaptureDeviceInput
    // — no UID→AudioDeviceID translation needed.
    @ObservationIgnored private let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
    )
    @ObservationIgnored private var devices: [AVCaptureDevice] = []
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
        self.devices = self.discoverySession.devices
        if let param = self.inputAudioDevice.parameter as? StringParameter
        {
            param.options = self.devices.map(\.localizedName)
        }
    }

    /// Resolve the AVCaptureDevice the user has picked in the dropdown, or
    /// the system default audio input if no selection (or the named device
    /// is gone).
    private func resolveSelectedAudioDevice() -> AVCaptureDevice?
    {
        if let name = self.inputAudioDevice.value, !name.isEmpty,
           let match = self.devices.first(where: { $0.localizedName == name })
        {
            return match
        }
        return AVCaptureDevice.default(for: .audio)
    }

    override public func startExecution(context: GraphExecutionContext) {
        super.startExecution(context: context)
        self.requestAudioSetupIfNeeded()
    }

    private func requestAudioSetupIfNeeded()
    {
        guard !self.didRequestAudioSetup else { return }
        self.didRequestAudioSetup = true

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                self.setupCaptureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    if granted {
                        print("Granted Mic Access")
                        DispatchQueue.main.async { self?.setupCaptureSession() }
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

    override public func stopExecution(context: GraphExecutionContext)
    {
        super.stopExecution(context: context)
        if self.captureSession.isRunning
        {
            self.captureSession.stopRunning()
        }
    }

    override public func disableExecution(context: GraphExecutionContext)
    {
        super.disableExecution(context: context)
        if self.captureSession.isRunning
        {
            self.captureSession.stopRunning()
        }
    }

    override public func execute(context: GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer)
    {
        self.requestAudioSetupIfNeeded()

        // Device re-routing: picking a new device rebuilds the capture
        // session's input. AVCaptureSession supports this cleanly via
        // beginConfiguration/commit — no engine lifecycle to fight.
        if self.inputAudioDevice.valueDidChange, self.didRequestAudioSetup
        {
            self.setupCaptureSession()
        }

        if self.inputSmoothing.valueDidChange || self.inputBands.valueDidChange,
           let smoothing = self.inputSmoothing.value,
           let bands = self.inputBands.value
        {
            self.smoothing = smoothing
            self.bands = bands
            
            self.createFilterBank(sampleRate: self.filterBank?.sampleRate ?? 48000.0, bandCount: self.bands, normalizedSmoothing: self.smoothing)
        }
        
        if self.inputAttack.valueDidChange || self.inputRelease.valueDidChange,
           let attack = self.inputAttack.value,
           let release = self.inputRelease.value
        {
                self.filterBank?.attackMS = attack.isFinite ? attack : 10.0
                self.filterBank?.releaseMS = release.isFinite ? release : 10.0
        }
        
        guard let filterBank else { return }

        let targetVideoFrameRate:Float = 200
        let numSamplesInAFrame = Int(round( filterBank.sampleRate / targetVideoFrameRate ) )
            
        let batchSize = min(numSamplesInAFrame, self.samples.count)
        let rawGain = self.inputGain.value ?? 1.0
        let gain: Float = rawGain.isFinite ? rawGain : 1.0

        guard batchSize > 0 else { return }

        let gainedBatch: [Float] = self.samples.prefix(batchSize).map { s in
            let v = s * gain
            return v.isFinite ? v : 0
        }

        let output = filterBank.processAudioData(samples: gainedBatch)

        let normalizedOutput = ContiguousArray<Float>(output.map { ($0.isNaN || $0.isInfinite) ? 0.0 : $0 })

        self.outputSpectrum.send( normalizedOutput )

        if self.showSettings
        {
            self.visualizationBandValues = Array(normalizedOutput)
        }

        self.samples = Array<Float>(self.samples.dropFirst(batchSize))

        if self.samples.count > self.maxSamples
        {
            let overrun =  self.samples.count - self.maxSamples
            self.samples = Array<Float>(self.samples.dropLast(overrun) )
        }
    }
    
    var filterBank:SimpleFilterBank? = nil

    // Running list of samples
    var samples = [Float]()
    let maxSamples = 4096
    
    private var bands:Int = 8
    private var smoothing:Float = 0.0
    
    func createFilterBank(sampleRate:Float, bandCount:Int, normalizedSmoothing:Float)
    {
        // Clamp inputs so a zero/NaN sampleRate or NaN smoothing can never
        // produce NaN biquad coefficients (sin/cos of ∞ → NaN propagates
        // through the whole filter bank otherwise).
        let safeRate: Float = (sampleRate.isFinite && sampleRate > 0) ? sampleRate : 48000
        let safeBands = max(1, bandCount)
        let safeSmoothing: Float = normalizedSmoothing.isFinite ? normalizedSmoothing : 0

        let q = remap(safeSmoothing, 1.0, 0.0, 0.0, Float(safeBands))
        let safeQ: Float = (q.isFinite && q > 0) ? q : Float(safeBands)

        self.filterBank = SimpleFilterBank(sampleRate: safeRate,
                                           bandCount: safeBands,
                                           fMin: 20.0,
                                           fMax: 15_000.0,
                                           Q: safeQ,
                                           dbFloor: -120.0)

        let rawAttack = self.inputAttack.value ?? 10.0
        let rawRelease = self.inputRelease.value ?? 10.0
        self.filterBank?.attackMS = rawAttack.isFinite ? rawAttack : 10.0
        self.filterBank?.releaseMS = rawRelease.isFinite ? rawRelease : 10.0
    }
    
    var lastCalledTime:TimeInterval = Date.timeIntervalSinceReferenceDate
    
    /// Called on the capture queue for every audio sample buffer. Extracts
    /// the first channel's Float32 samples and hands them off to the filter
    /// bank's sample queue on the main thread.
    fileprivate func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        let asbd = asbdPtr.pointee
        let sampleRate = Float(asbd.mSampleRate)
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)

        // AVCaptureAudioDataOutput on macOS delivers Float32 LPCM by default.
        // If a device delivers anything else, skip the buffer — better silent
        // drop than garbage samples into the filter bank.
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

        let stride = isInterleaved ? channels : 1
        let frameCount = Int(firstBuffer.mDataByteSize) / (stride * MemoryLayout<Float>.size)
        let floats = dataPtr.assumingMemoryBound(to: Float.self)

        var newSamples: [Float] = []
        newSamples.reserveCapacity(frameCount)
        for i in 0..<frameCount
        {
            let s = floats[i * stride]
            newSamples.append(s.isFinite ? s : 0)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Lazily (re-)build the filter bank when the stream's sample rate
            // changes or differs from the last-seen rate.
            if sampleRate.isFinite, sampleRate > 0,
               self.filterBank == nil || self.filterBank?.sampleRate != sampleRate
            {
                self.createFilterBank(sampleRate: sampleRate,
                                      bandCount: self.bands,
                                      normalizedSmoothing: self.smoothing)
            }

            self.samples.append(contentsOf: newSamples)
        }
    }

    /// Build (or rebuild) the capture session for the currently-selected
    /// device. Safe to call any number of times.
    ///
    /// Recreates the AVCaptureSession itself on each call rather than
    /// reconfiguring-in-place. Some virtual devices (e.g. Rogue Amoeba's
    /// Loopback) deliver streams whose format the existing session's
    /// CMIO audio converter can't re-negotiate mid-session, surfacing as
    /// `AudioConverterSetProperty(dbca) failed (pcm!)` and a silent output.
    /// A fresh session forces a fresh converter, which can build the right
    /// graph for whatever the new device offers.
    private func setupCaptureSession()
    {
        guard let device = self.resolveSelectedAudioDevice() else
        {
            print("AudioSpectrum: no audio input device available")
            return
        }

        // Tear down the previous session entirely — this guarantees the
        // CMIO audio converter for the old device is released before the
        // new one is constructed.
        if self.captureSession.isRunning
        {
            self.captureSession.stopRunning()
        }

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
            // Pin the output format. Without this, CMIO picks its own target
            // and chokes on virtual-device streams whose native format it
            // can't auto-negotiate (AudioConverterSetProperty(dbca) = pcm!).
            // Asking for mono 48 kHz Float32 LPCM gives the converter an
            // unambiguous destination to build toward, and matches what
            // processAudioSampleBuffer() already extracts.
            output.audioSettings = [
                AVFormatIDKey:              kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey:     32,
                AVLinearPCMIsFloatKey:      true,
                AVLinearPCMIsBigEndianKey:  false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey:            48_000.0,
                AVNumberOfChannelsKey:      1
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

        // New device may deliver at a different rate — drain the old queue
        // so the first fresh sample buffer drives the filter-bank rebuild.
        self.samples.removeAll(keepingCapacity: true)
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


