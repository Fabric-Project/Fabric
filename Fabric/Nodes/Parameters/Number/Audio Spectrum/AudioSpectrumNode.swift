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
    class SignalProcessing {
        
        static func rms(data: UnsafeMutablePointer<Float>, frameLength: UInt) -> Float
        {
            var val : Float = 0
            vDSP_measqv(data, 1, &val, frameLength)

            var db = 10*log10f(val)
            //inverse dB to +ve range where 0(silent) -> 160(loudest)
            db = 160 + db;
            //Only take into account range from 120->160, so FSR = 40
            db = db - 120

            let dividor = Float(40/0.3)
            var adjustedVal = 0.3 + db/dividor

            //cutoff
            if (adjustedVal < 0.3) {
                adjustedVal = 0.3
            } else if (adjustedVal > 0.6) {
                adjustedVal = 0.6
            }
            
            return adjustedVal
        }
        
        static func downsample(data: UnsafeMutablePointer<Float>, decimationFactor:Int) -> [Float] {
            
            var samples = [Float](repeating: 0, count: 1024)

            //fill in real input part with audio samples
            for i in 0...1023 {
                samples[i] = data[i]
            }
            
            let noiseFloor:Float = -120.0
            guard decimationFactor <= samples.count else {
                return []
            }
            
//            var samples = audioSamples
                // convert to decibels
            vDSP.absolute(samples, result: &samples)
            
            vDSP.convert(amplitude: samples, toDecibels: &samples, zeroReference: 1 )
            
//            samples = vDSP.clip(samples, to: noiseFloor...0)
            
                // downsample
            var filter = [Float](repeating: 1.0 / Float(decimationFactor), count:decimationFactor)
            
//            if antialias == false {
//                filter = [1.0]
//            }
            
            let downsamplesLength = Int(samples.count / decimationFactor)
            var downsamples = [Float](repeating: 0.0, count:downsamplesLength)
            
            vDSP.downsample(samples, decimationFactor: decimationFactor, filter: filter, result: &downsamples)

//            #if os(macOS)
//            vDSP_desamp(samples, vDSP_Stride(decimationFactor), filter, &downsamples, vDSP_Length(downsamplesLength), vDSP_Length(filter.count))
//            #else
//            if getOSMajorVersion() >= 17 {
//                vDSP.downsample(audioSamplesD, decimationFactor: decimationFactor, filter: filter, result: &downsamples)
//            } else {
//                vDSP_desampD(audioSamplesD, vDSP_Stride(decimationFactor), filter, &downsamples, vDSP_Length(downsamplesLength), vDSP_Length(filter.count))
//            }
//            #endif
            
            // Normalize from [dbFloor, 0] → [0, 1]
            var normalized = [Float](repeating: 0, count: downsamples.count)
//
            let epsilon: Float = 0.0
            var scale = 1.0 / (epsilon - noiseFloor)
            var add   = -noiseFloor / (epsilon - noiseFloor)

            vDSP_vsmsa(downsamples, 1, &scale, &add, &normalized, 1, vDSP_Length(downsamples.count))
        
//            let audioSamplesMaximum = vDSP.maximum(downsamples)
//            
//            var renormalized = [Float](repeating: 0, count: downsamples.count)
//
//            for i in 0...downsamples.count - 1
//            {
////                if audioSamplesMaximum != noiseFloor
////                {
//                    let rescaled = (downsamples[i] - noiseFloor) / (audioSamplesMaximum - noiseFloor + epsilon)
//                    renormalized.append(rescaled)
////                }
//                
//            }
//            
            return normalized
        }
        
        static func fft(data: UnsafeMutablePointer<Float>, setup: OpaquePointer, window:UnsafeMutablePointer<Float>, smoothingFactor:Float, decimationFactor: Int) -> [Float] {
            //output setup
            var realIn = [Float](repeating: 0, count: 1024)
            var imagIn = [Float](repeating: 0, count: 1024)
            var realOut = [Float](repeating: 0, count: 1024)
            var imagOut = [Float](repeating: 0, count: 1024)

            //fill in real input part with audio samples
            for i in 0...1023 {
                realIn[i] = data[i]
            }

            //our results are now inside realOut and imagOut
            vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

            return realOut.withUnsafeMutableBufferPointer { realOutBufferPointer in

                return imagOut.withUnsafeMutableBufferPointer { imgOutBufferPointer in

                    //package it inside a complex vector representation used in the vDSP framework
                    let complex = DSPSplitComplex(realp: realOutBufferPointer.baseAddress!, imagp: imgOutBufferPointer.baseAddress!)

                    //setup magnitude output
                    var magnitudes = [Float](repeating: 0, count: 512)
                    vDSP.squareMagnitudes(complex, result: &magnitudes)
                    
                    let fs: Float = 48000.0

//                    let M = 240
//                    let fMin: Float = 20
//                    let fMax: Float = fs * 0.5
//
//                    var logFreqs = [Float](repeating: 0, count: M)
//                    let logMin = log10f(fMin), logMax = log10f(fMax)
//                    let d = (logMax - logMin) / Float(M - 1)
//                    vDSP_vgen([logMin], [d], &logFreqs, 1, vDSP_Length(M))
//                    
//                    logFreqs = vForce.pow(bases: logFreqs, exponents: [Float](repeating: 10.0, count: M) )
////                    vvpowf(&logFreqs, [10.0], &logFreqs, [Int32(M)]) // log10 -> Hz
//
//                    // Map target freqs to fractional bin indices in the linear spectrum
//                    var fracIdx = [Float](repeating: 0, count: M)
//                    var binsPerHz = Float(1024) / fs        // k = f * N / fs
//                    vDSP_vsmul(&logFreqs, 1, &binsPerHz, &fracIdx, 1, vDSP_Length(M))
//
//                    // Interpolate from 'power' onto log-spaced centers
//                    var logPower = [Float](repeating: 0, count: M)
//                    vDSP_vlint(magnitudes, fracIdx, 1, &logPower, 1, vDSP_Length(M), vDSP_Length(512))
//
//                    // Now take dB/normalize and draw
//                    var db = [Float](repeating: 0, count: M)
//                    vDSP.convert(power: logPower, toDecibels: &db, zeroReference: 1.0)
                    
                    // freq[k] = k * fs / N, k = 0..halfN-1
                    var k = [Float](repeating: 0, count: 512)
                    vDSP_vramp([0], [1], &k, 1, vDSP_Length(512))
                    var freqs = [Float](repeating: 0, count: 512)
                    var hzPerBin = fs / Float(1024)
                    vDSP_vsmul(k, 1, &hzPerBin, &freqs, 1, vDSP_Length(512))

                    
//                     If you have POWER spectrum:
//                    var powerWeighted = [Float](repeating: 0, count: 512)
//                    vDSP_vmul(magnitudes, 1, freqs, 1, &powerWeighted, 1, vDSP_Length(512))
                    
                    // If instead you have AMPLITUDE spectrum:
                    var sqrtFreqs = [Float](repeating: 0, count: 512)
                    vvsqrtf(&sqrtFreqs, &freqs, [Int32(512)])
                    var ampWeighted = [Float](repeating: 0, count: 512)
                    vDSP_vmul(magnitudes, 1, sqrtFreqs, 1, &ampWeighted, 1, vDSP_Length(512))
                    
                    
                    //normalize
                    let scalingFactor = Float(1.0/512.0)
                    var normalizedMagnitudes = vDSP.multiply(scalingFactor, ampWeighted)


                    var smoothing:Float = smoothingFactor
                    vDSP_vsmul(&normalizedMagnitudes, 1, &smoothing, window, 1, 512)

                    // Add epsilon to avoid log(0)
                    let epsilon: Float = 1e-12
                    normalizedMagnitudes = vDSP.add(epsilon, normalizedMagnitudes)

//                    var decibels = [Float](repeating: 0.0, count: 512)
//
//                    vDSP.convert(power: normalizedMagnitudes, toDecibels: &decibels, zeroReference: 1.0)

                    // Normalize from [dbFloor, 0] → [0, 1]
//                    let dbFloor: Float = -120.0
//                    var normalized = [Float](repeating: 0, count: 512)
//
//                    var scale = 1.0 / (epsilon - dbFloor)
//                    var add   = -dbFloor / (epsilon - dbFloor)
//
//                    vDSP_vsmsa(decibels, 1, &scale, &add, &normalized, 1, 512)


                    
                    let filter = [Float](repeating: 1.0 / Float(decimationFactor), count:decimationFactor)
                    let downsamplesLength = Int(normalizedMagnitudes.count / decimationFactor)
                    var downsamples = [Float](repeating: 0.0, count:downsamplesLength)
                    
                    vDSP.downsample(normalizedMagnitudes, decimationFactor: decimationFactor, filter: filter, result: &downsamples)
                    return downsamples
                }
            }
        }

    
        
        // CLOSEST
//        static func fft(data: UnsafeMutablePointer<Float>, setup: OpaquePointer, window:UnsafeMutablePointer<Float>) -> [Float] {
//            //output setup
//            var realIn = [Float](repeating: 0, count: 1024)
//            var imagIn = [Float](repeating: 0, count: 1024)
//            var realOut = [Float](repeating: 0, count: 1024)
//            var imagOut = [Float](repeating: 0, count: 1024)
//            
//            //fill in real input part with audio samples
//            for i in 0...1023 {
//                realIn[i] = data[i]
//            }
//        
//            //our results are now inside realOut and imagOut
//            vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)
//            
//            return realOut.withUnsafeMutableBufferPointer { realOutBufferPointer in
//                
//                return imagOut.withUnsafeMutableBufferPointer { imgOutBufferPointer in
//                    
//                    //package it inside a complex vector representation used in the vDSP framework
//                    let complex = DSPSplitComplex(realp: realOutBufferPointer.baseAddress!, imagp: imgOutBufferPointer.baseAddress!)
//                    
//                    //setup magnitude output
//                    var magnitudes = [Float](repeating: 0, count: 512)
//                    vDSP.squareMagnitudes(complex, result: &magnitudes)
//
//                    var smoothing:Float = 0.75
//                    vDSP_vsmul(&magnitudes, 1, &smoothing, window, 1, 512)
//                    
//                    
//                    //normalize
//                    let scalingFactor = Float(1.0/512.0)
//                    var normalizedMagnitudes = vDSP.multiply(scalingFactor, magnitudes)
//                    
//
//                    // Add epsilon to avoid log(0)
//                    let epsilon: Float = 1e-12
//                    normalizedMagnitudes = vDSP.add(epsilon, normalizedMagnitudes)
//                    
//                    var decibels = [Float](repeating: 0.0, count: 512)
//
//                    vDSP.convert(power: normalizedMagnitudes, toDecibels: &decibels, zeroReference: 1.0)
//                    
//                    // Normalize from [dbFloor, 0] → [0, 1]
//                    let dbFloor: Float = -120.0
//                    var normalized = [Float](repeating: 0, count: 512)
//
//                    var scale = 1.0 / (epsilon - dbFloor)
//                    var add   = -dbFloor / (epsilon - dbFloor)
//
//                    vDSP_vsmsa(decibels, 1, &scale, &add, &normalized, 1, 512)
//
//                    // Clamp to [0,1] just to be safe
////                    var low: Float = 0.0
////                    var high: Float = 1.0
////                    vDSP_vclip(normalized, 1, &low, &high, &normalized, 1, 512)
//
//                    return normalized
//                }
//            }
//        }
        
        
        
//
//        static func fft(data: UnsafeMutablePointer<Float>,
//                        setup: OpaquePointer,
//                        window: [Float]) -> [Float] {
//
//            // Copy time samples
//            var realIn = [Float](repeating: 0, count: 1024)
//            var imagIn = [Float](repeating: 0, count: 1024)
//            for i in 0..<1024 { realIn[i] = data[i] }
//
//            // Remove DC bias (helps first bin)
//            var mean: Float = vDSP.mean(realIn)
////            vDSP_meanv(&realIn, 1, &mean, 1024)
//            let negMean = -mean
//            realIn = vDSP.add(negMean, realIn)
////            vDSP_vsadd(&realIn, 1, &negMean, &realIn, 1, 1024)s
//
//            // Apply window in time domain
//            var realWindowed = [Float](repeating: 0, count: 1024)
//            vDSP_vmul(&realIn, 1, window, 1, &realWindowed, 1, 1024)
////            realIn = vDSP.multiply(addition: (a: realIn, b: window), 1.0)
//            
//            // FFT
//            var realOut = [Float](repeating: 0, count: 1024)
//            var imagOut = [Float](repeating: 0, count: 1024)
//            vDSP_DFT_Execute(setup, &realWindowed, &imagIn, &realOut, &imagOut)
//
//            // Power spectrum (first N/2 bins)
//            return realOut.withUnsafeMutableBufferPointer { realOutBufferPointer in
//                
//                return imagOut.withUnsafeMutableBufferPointer { imgOutBufferPointer in
//                    
//                    var power = [Float](repeating: 0, count: 512)
//                    
//                    let split = DSPSplitComplex(realp: realOutBufferPointer.baseAddress!, imagp: imgOutBufferPointer.baseAddress!)
//                    vDSP.squareMagnitudes(split, result: &power)
//                    
//                    // Optional overall scaling if you want (e.g., 1/N)
//                    var scalePow: Float = 1.0 / 512.0
////                    vDSP_vsmul(&power, 1, &scalePow, &power, 1, 512)
//                    power = vDSP.multiply(scalePow, power)
//                    
//                    // dB with proper reference (1.0 = 0 dB if input is ±1)
//                    var decibels = [Float](repeating: 0, count: 512)
//                    vDSP.convert(power: power, toDecibels: &decibels, zeroReference: 1.0)
//                    
//                    // Kill DC bin for display
//                    decibels[0] = -120
//                    
//                    // Normalize dB → [0,1]
//                    let dbFloor: Float = -80
//                    var norm = [Float](repeating: 0, count: 512)
//                    var normScale = 1.0 / (0.0 - dbFloor)
//                    var normAdd   = -dbFloor * normScale
//                    vDSP_vsmsa(&decibels, 1, &normScale, &normAdd, &norm, 1, 512)
//                    
//                   // var lo: Float = 0, hi: Float = 1
////                    vDSP_vclip(&norm, 1, &lo, &hi, &norm, 1, 512)
////                    return vDSP.clip(norm, to: 0...1)
//                    
//                    return norm
//                }
//            }
//        }

        
        static func interpolate(current: Float, previous: Float) -> [Float]{
            var vals = [Float](repeating: 0, count: 11)
            vals[10] = current
            vals[5] = (current + previous)/2
            vals[2] = (vals[5] + previous)/2
            vals[1] = (vals[2] + previous)/2
            vals[8] = (vals[5] + current)/2
            vals[9] = (vals[10] + current)/2
            vals[7] = (vals[5] + vals[9])/2
            vals[6] = (vals[5] + vals[7])/2
            vals[3] = (vals[1] + vals[5])/2
            vals[4] = (vals[3] + vals[5])/2
            vals[0] = (previous + vals[1])/2
            
            return vals
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
        
        if self.inputSmoothing.valueDidChange,
           let smoothing = self.inputSmoothing.value
        {
            self.smoothing = smoothing
        }
        
        if self.inputDecimation.valueDidChange,
           let decimation = self.inputDecimation.value
        {
            self.decimation = decimation
        }
        
        let output = ContiguousArray<Float>(self.fftMagnitudes)
        self.outputSpectrum.send( output )
        
    }
    
    var prevRMSValue : Float = 0.3
    var fftMagnitudes = [Float](repeating: 0, count: 512)
    //fft setup object for 1024 values going forward (time domain -> frequency domain)
    let fftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD)
    var window: [Float] = [Float](repeating: 0, count: 1024)
    
    var smoothing:Float = 0.5;
    var decimation:Int = 8
    
    func processAudioData(buffer: AVAudioPCMBuffer)
    {
        guard let channelData = buffer.floatChannelData?[0]
        else
        {
            return
        }
        
//        let frames = buffer.frameLength
        
//        //rms
//        let rmsValue = SignalProcessing.rms(data: channelData, frameLength: UInt(frames))
//        let interpolatedResults = SignalProcessing.interpolate(current: rmsValue, previous: prevRMSValue)
//        prevRMSValue = rmsValue
        
        //fft
        let fftMagnitudes = SignalProcessing.fft(data: channelData, setup: fftSetup!, window: &window, smoothingFactor: self.smoothing, decimationFactor: self.decimation)
//        let fftMagnitudes = SignalProcessing.downsample(data: channelData, decimationFactor: 8)

        DispatchQueue.main.async {
            self.fftMagnitudes = fftMagnitudes
        }
    }
    
    
    private func setupAudioShit()
    {
        do
        {
//            vDSP_hann_window(&window, vDSP_Length(1024), Int32(vDSP_HANN_NORM))
            vDSP_blkman_window(&window, vDSP_Length(1024), 0)
            
            let inputNode = self.engine.inputNode
            
            if inputNode.inputFormat(forBus: 0).sampleRate == 0 {
                exit(0)
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            print(inputNode)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, time) in
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


