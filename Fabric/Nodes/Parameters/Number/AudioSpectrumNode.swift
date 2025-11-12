//
//  AudioSpectrumNode.swift
//  Fabric
//
//  Created by Anton Marini on 11/4/25.
//

import Foundation
import Satin
import simd
import AVFAudio
import AVFoundation
import Accelerate
import CoreAudio
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
                let ePrev = env[k]
                let e = (norm > ePrev) ? (ePrev + a * (norm - ePrev))
                                       : (ePrev + r * (norm - ePrev))
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
            ("inputAudioDevice", ParameterPort(parameter: StringParameter("Device Name", "", .dropdown))),
            ("inputBands", ParameterPort(parameter: IntParameter("Bands", 8, 1, 256, .inputfield))),
            ("inputSmoothing", ParameterPort(parameter: FloatParameter("Smoothing", 0.0, 0.0, 1.0, .slider))),
            ("inputAttack", ParameterPort(parameter: FloatParameter("Attack", 0.0, 0.0, 100.0, .slider))),
            ("inputRelease", ParameterPort(parameter: FloatParameter("Release", 0.0, 0.0, 100.0, .slider))),
            ("outputSpectrum", NodePort<ContiguousArray<Float>>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    public var inputAudioDevice:ParameterPort<String> { port(named: "inputAudioDevice") }
    public var inputBands:ParameterPort<Int> { port(named: "inputBands") }
    public var inputSmoothing:ParameterPort<Float> { port(named: "inputSmoothing") }
    public var inputAttack:ParameterPort<Float> { port(named: "inputAttack") }
    public var inputRelease:ParameterPort<Float> { port(named: "inputRelease") }
    public var outputSpectrum:NodePort<ContiguousArray<Float>> { port(named: "outputSpectrum") }

    private var engine = AVAudioEngine()
    private var inputNode: AVAudioInputNode? = nil
    

    override public func startExecution(context: GraphExecutionContext) {
        super.startExecution(context: context)

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: // The user has previously granted access to the camera.
                self.setupAudioShit()
                return
            case .notDetermined: // The user has not yet been asked for camera access.
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    if granted {
                        print("Granted Mic Access")
                        self.setupAudioShit()
                    }
                    else
                    {
                        print("Not Granted Mic Access")
                    }
                }
            
            case .denied: // The user has previously denied access.
            print("Not Granted Mic Access")
                return

            case .restricted: // The user can't grant access due to restrictions.
                print("Restricted from Granting Mic Access")
                return
        @unknown default:
            print("Restricted from Granting Mic Access")
        }
    }
    
    override public func stopExecution(context: GraphExecutionContext)
    {
        super.stopExecution(context: context)
        
        self.engine.stop()
    }
    
//    override public func enableExecution(context:GraphExecutionContext)
//    {
//        super.enableExecution(context: context)
//    }

    override public func disableExecution(context: GraphExecutionContext)
    {
        super.disableExecution(context: context)
        
        self.engine.pause()
    }
    
    override public func execute(context: GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer)
    {
        
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
                self.filterBank?.attackMS = attack
                self.filterBank?.releaseMS = release
        }
        
        guard let filterBank else { return }

        let targetVideoFrameRate:Float = 200
        let numSamplesInAFrame = Int(round( filterBank.sampleRate / targetVideoFrameRate ) )
            
        let batchSize = min(numSamplesInAFrame, self.samples.count)
        let batchOfSamples = self.samples[ 0 ..< batchSize]
        
        let output = filterBank.processAudioData(samples: batchOfSamples)
        
        self.outputSpectrum.send( output )
        
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
        // No idea about this q calc?
        let q = remap(normalizedSmoothing, 1.0, 0.0, 0.0, Float(bandCount) )
        
        self.filterBank = SimpleFilterBank(sampleRate: sampleRate,
                                           bandCount: bandCount,
                                           fMin: 33.0,
                                           fMax: 15_000.0,//22_000.0,
                                           Q: q,
                                           dbFloor: -120.0)
        
        self.filterBank?.attackMS = self.inputAttack.value ?? 10.0
        self.filterBank?.releaseMS = self.inputRelease.value ?? 10.0
    }
    
    var lastCalledTime:TimeInterval = Date.timeIntervalSinceReferenceDate
    
    func processAudioData(buffer: AVAudioPCMBuffer)
    {
        let count = buffer.frameLength
        
        if let floatChannelData = buffer.floatChannelData
        {
            var newSamples: [Float] = []
            
            for i in 0 ..< count
            {
                newSamples.append(floatChannelData[0][Int(i)])
            }
            
            DispatchQueue.main.async { [weak self] in
                
                guard let self else { return }
                
                self.samples.append(contentsOf: newSamples)
            }
        }
        
        return
    }
    
    private func setupAudioShit()
    {
        do
        {
            let tapNode = self.engine.inputNode
            
            let sampleRate = Float(tapNode.inputFormat(forBus: 0).sampleRate)
            
            if self.filterBank == nil
            {
                self.createFilterBank(sampleRate:sampleRate, bandCount: self.bands, normalizedSmoothing: self.smoothing)
            }
            
            tapNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { (buffer, time) in
                self.processAudioData(buffer: buffer)
            }
            
            try self.engine.start()
            
            print(tapNode)


        }
        catch
        {
            print("Unable to start Audio Engine:", error)
        }
        
    }
}


