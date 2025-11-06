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

public class AudioSpectrumNode : Node
{

    final class SimpleFilterBank {
        // ---- Config ----
        var sampleRate: Float
        var bandCount: Int
        var fMin: Float
        var fMax: Float
        var Q: Float              // constant-Q feel (tweak if you like)
        var dbFloor: Float        // normalize floor
        
        // Add per-band envelope state (0..1)
         private var env = [Float]()

         // User knobs for feel (milliseconds)
         var attackMS: Float = 0
         var releaseMS: Float = 0
        
        
        // ---- Biquad coeffs per band (a0 normalized out; we store a1,a2 already divided) ----
        private var b0 = [Float]()
        private var b1 = [Float]()
        private var b2 = [Float]()
        private var a1 = [Float]()
        private var a2 = [Float]()

        // ---- Filter state (DF2T) per band ----
        private var z1 = [Float]()
        private var z2 = [Float]()

        // ---- Scratch buffer for filtered block ----
        private var work = [Float]()

        init(sampleRate: Double,
             bandCount: Int,
             fMin: Float = 10.0,
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

        // Call this if bandCount, fMin/fMax, Q, or sampleRate changes.
        func buildBands() {
            b0 = .init(repeating: 0, count: bandCount)
            b1 = .init(repeating: 0, count: bandCount)
            b2 = .init(repeating: 0, count: bandCount)
            a1 = .init(repeating: 0, count: bandCount)
            a2 = .init(repeating: 0, count: bandCount)
            z1 = .init(repeating: 0, count: bandCount)
            z2 = .init(repeating: 0, count: bandCount)

            // Log-spaced center frequencies
            let r = fMax / fMin
            for k in 0..<bandCount {
                let t  = bandCount > 1 ? Float(k) / Float(bandCount - 1) : 0
                let fc = fMin * powf(r, t)
                let w0 = 2.0 * .pi * (fc / sampleRate)
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

                // Normalize by a0
                b0k /= a0k; b1k /= a0k; b2k /= a0k
                a1k /= a0k; a2k /= a0k

                b0[k] = b0k; b1[k] = b1k; b2[k] = b2k
                a1[k] = a1k; a2[k] = a2k
            }
        }

        // Main entry: returns [0,1] per band
        func processAudioData(buffer: AVAudioPCMBuffer) -> ContiguousArray<Float> {
                guard let channelData = buffer.floatChannelData?[0] else {
                    return ContiguousArray<Float>()
                }

                let n = Int(buffer.frameLength)
                if work.count < n { work = .init(repeating: 0, count: n) }

                // Precompute block-based smoothing coefficients
                // (attack/release over one callback; simple, legible)
                let hop = Float(n) / sampleRate
                let a:Float = 1 - expf(-hop / max(attackMS * 0.001, 1e-12))
                let r:Float = 1 - expf(-hop / max(releaseMS * 0.001, 1e-12))

                var out = ContiguousArray<Float>(repeating: 0, count: bandCount)

                for k in 0..<bandCount {
                    // --- filter pass (unchanged) ---
                    var zz1 = z1[k], zz2 = z2[k]
                    let b0k = b0[k], b1k = b1[k], b2k = b2[k], a1k = a1[k], a2k = a2[k]

                    for i in 0..<n {
                        let x = channelData[i]
                        let y = b0k * x + zz1
                        zz1 = b1k * x - a1k * y + zz2
                        zz2 = b2k * x - a2k * y
                        work[i] = y
                    }
                    z1[k] = zz1; z2[k] = zz2

                    // --- energy measure (unchanged) ---
                    var rms: Float = 0
                    vDSP_rmsqv(work, 1, &rms, vDSP_Length(n))
                    var db = 20.0 * log10f(max(rms, 1e-12))
                    if db < dbFloor { db = dbFloor }
                    let norm = min(max((db - dbFloor) / (0 - dbFloor), 0), 1)

                    // --- envelope with separate attack/release ---
                    let ePrev = env[k]
                    let e = (norm > ePrev)
                        ? ePrev + a * (norm - ePrev)    // faster rise
                        : ePrev + r * (norm - ePrev)    // slower fall
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
            ("inputDecimation", ParameterPort(parameter: IntParameter("Decimation", 8, 1, 128, .inputfield))),
            ("inputSmoothing", ParameterPort(parameter: FloatParameter("Smoothing", 0.5, 0.0, 1.0, .slider))),
            ("outputSpectrum", NodePort<ContiguousArray<Float>>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    public var inputAudioDevice:ParameterPort<String> { port(named: "inputAudioDevice") }
    public var inputDecimation:ParameterPort<Int> { port(named: "inputDecimation") }
    public var inputSmoothing:ParameterPort<Float> { port(named: "inputSmoothing") }
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
        }
    }
    
    override public func execute(context: GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer)
    {
        
//        if self.inputSmoothing.valueDidChange,
//           let smoothing = self.inputSmoothing.value
//        {
//            self.smoothing = smoothing
//        }
//        
//        if self.inputDecimation.valueDidChange,
//           let decimation = self.inputDecimation.value
//        {
//            self.decimation = decimation
//        }
        
        let output = ContiguousArray<Float>(self.fftMagnitudes)
        self.outputSpectrum.send( output )
        
    }
    
    static let sampleCount = 1024
    static let sampleCountHalf = AudioSpectrumNode.sampleCount / 2

    var fftMagnitudes = ContiguousArray<Float>()

    let filterBank = SimpleFilterBank(sampleRate: 48000,
                                      bandCount: 128,
                                      fMin: 33.0,
                                      fMax: 22_000.0,
                                      Q: 32,
                                      dbFloor: -120
    )
    
    func processAudioData(buffer: AVAudioPCMBuffer)
    {
        let output = self.filterBank.processAudioData(buffer: buffer)
        
        DispatchQueue.main.async {
            self.fftMagnitudes = output
        }
    }
    
    private func setupAudioShit()
    {
        do
        {//            vDSP_blkman_window(&window, vDSP_Length(1024), 0)
            
            let inputNode = self.engine.inputNode
            
            if inputNode.inputFormat(forBus: 0).sampleRate == 0 {
                exit(0)
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            print(inputNode)

            inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(AudioSpectrumNode.sampleCount), format: recordingFormat) { (buffer, time) in
                self.processAudioData(buffer: buffer)
            }

            try self.engine.start()

        }
        catch
        {
            print("Unable to start Audio Engine:", error)
        }
        
    }
}


