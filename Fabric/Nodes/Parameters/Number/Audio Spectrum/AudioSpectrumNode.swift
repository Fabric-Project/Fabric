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
        
        static func fft(data: UnsafeMutablePointer<Float>, setup: OpaquePointer) -> [Float] {
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
                    var complex = DSPSplitComplex(realp: realOutBufferPointer.baseAddress!, imagp: imgOutBufferPointer.baseAddress!)
                    
                    //setup magnitude output
                    var magnitudes = [Float](repeating: 0, count: 512)
                    
                    //calculate magnitude results
                    vDSP_zvabs(&complex, 1, &magnitudes, 1, 512)
                    
                    //normalize
                    var normalizedMagnitudes = [Float](repeating: 0.0, count: 512)
                    var scalingFactor = Float(1.0/512.0)
                    vDSP_vsmul(&magnitudes, 1, &scalingFactor, &normalizedMagnitudes, 1, 512)

                    return normalizedMagnitudes
                }
            }
        }
        
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
            ("outputSpectrum", NodePort<ContiguousArray<Float>>(name: NumberNode.name , kind: .Outlet)),
        ]
    }
    
    public var inputAudioDevice:ParameterPort<String> { port(named: "inputAudioDevice") }
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

        
        // Warm up Main Mixer
        
    }
    
    override public func execute(context: GraphExecutionContext, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: any MTLCommandBuffer)
    {
        
        let output = ContiguousArray<Float>(self.fftMagnitudes)
        self.outputSpectrum.send( output )
        
    }
    
    var prevRMSValue : Float = 0.3
    var fftMagnitudes = [Float](repeating: 0, count: 512)
    //fft setup object for 1024 values going forward (time domain -> frequency domain)
    let fftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD)

    func processAudioData(buffer: AVAudioPCMBuffer)
    {
        guard let channelData = buffer.floatChannelData?[0]
        else
        {
            return
        }
        
        let frames = buffer.frameLength
        
        //rms
        let rmsValue = SignalProcessing.rms(data: channelData, frameLength: UInt(frames))
        let interpolatedResults = SignalProcessing.interpolate(current: rmsValue, previous: prevRMSValue)
        prevRMSValue = rmsValue
        
        //fft
        let fftMagnitudes =  SignalProcessing.fft(data: channelData, setup: fftSetup!)
         
//        print(/*fftMagnitudes*/.first)
        DispatchQueue.main.sync {
            self.fftMagnitudes = fftMagnitudes
        }
    }
    
    
    private func setupAudioShit()
    {
//        _ = self.engine.mainMixerNode
//
//        self.engine.prepare()
        
        do
        {
//            var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
//                                                             mScope: kAudioObjectPropertyScopeGlobal,
//                                                             mElement: kAudioObjectPropertyElementMain)
//            
//            var propertySize:UInt32 = UInt32( MemoryLayout<UInt32>.size )
//            
//            var outputDeviceID: AudioObjectID = 0
//            
//            var err: OSStatus = noErr
//           
////            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, <#T##inQualifierDataSize: UInt32##UInt32#>, <#T##inQualifierData: UnsafeRawPointer?##UnsafeRawPointer?#>, <#T##ioDataSize: UnsafeMutablePointer<UInt32>##UnsafeMutablePointer<UInt32>#>, <#T##outData: UnsafeMutableRawPointer##UnsafeMutableRawPointer#>)
//            err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
//                                             &propertyAddress, 0, nil, &propertySize, &outputDeviceID);
            let inputNode = self.engine.inputNode
            
            if inputNode.inputFormat(forBus: 0).sampleRate == 0 {
                exit(0)
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            
//            print("Setting Audio Input to device \(outputDeviceID)")

//            let inputNode = AVAudioIONode()
//            try inputNode.auAudioUnit.setDeviceID(outputDeviceID)
//            try inputNode.auAudioUnit.startHardware()
//
//            self.engine.connect(inputNode, to: self.engine.mainMixerNode, format: nil)
            
//            self.engine.inputNode.auAudioUnit.stopHardware()
//            try self.engine.inputNode.auAudioUnit.setDeviceID(outputDeviceID)
//            try self.engine.inputNode.auAudioUnit.startHardware()
            

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


