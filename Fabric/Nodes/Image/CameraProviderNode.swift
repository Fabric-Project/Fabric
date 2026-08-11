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
#if os(macOS)
import CoreMediaIO
import VideoToolbox
import MediaToolbox
#endif

private let CameraProviderNodeInitializer: Void = {

    print("One Time Global setup for CameraProviderNode")

    #if os(macOS)
    // Register professional video workflow codecs (ProRes, etc.) - macOS only
    VTRegisterProfessionalVideoWorkflowVideoDecoders()
    VTRegisterProfessionalVideoWorkflowVideoEncoders()
    MTRegisterProfessionalVideoWorkflowFormatReaders()

    // Enable screen capture devices - macOS only
    var allow : UInt32 = 1
    let sizeOfAllow = MemoryLayout.size(ofValue: allow)

    var property = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, UInt32(sizeOfAllow), &allow)

    property = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, UInt32(sizeOfAllow), &allow)
    #endif
}()

public class CameraProviderNode : Node
{
    class CaptureDelegate : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate
    {
        var pixelBuffer:CVPixelBuffer? = nil
        var gotNewPixelBuffer:Bool = false

        var captureQueue = DispatchQueue(label: "fabric.CameraTextureNode.capture_queue")

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
        {
            guard
                let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else
            {
                print("failed to get sample buffer")
                return
            }

            DispatchQueue.main.async {

                self.pixelBuffer = pixelBuffer
                self.gotNewPixelBuffer = true
            }
       }
    }
    
    
    override public class var name:String { "Camera Provider" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Connect to a Camera and stream video, providing Images"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputCamera", ParameterPort(parameter: StringParameter("Device Name", "", .dropdown, "Camera device to capture video from"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Live camera feed")),
        ]
    }

    public var inputCamera:ParameterPort<String>  { port(named: "inputCamera") }
    public var outputTexturePort:NodePort<FabricImage> { port(named: "outputTexturePort") }
    
    private let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external,], mediaType: nil, position:.unspecified)
    private var device: AVCaptureDevice? = nil
    private var captureSession: AVCaptureSession
    private let captureDelegate = CaptureDelegate()

    private var observer: Any? = nil
    
    private var devices = [AVCaptureDevice]()

    private var wasConnectedObserver:Any? = nil
    private var wasDisconnectedObserver:Any? = nil

    required public init(context:Context)
    {
        // Forces the initialization when the class is accessed
        _ = CameraProviderNodeInitializer
        
        self.captureSession = AVCaptureSession()

        super.init(context: context)
        
        self.commonPostSetup()
    }
    
    
    required public init(from decoder: any Decoder) throws
    {
        // Forces the initialization when the class is accessed
        _ = CameraProviderNodeInitializer
        
        self.captureSession = AVCaptureSession()
                
        try super.init(from:decoder)
        
        self.commonPostSetup()
    }
    
    func commonPostSetup()
    {
        self.wasConnectedObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main)
        { [weak self] notification in
            
            guard let self = self,
                  let inputCameraParam = self.inputCamera.parameter as? StringParameter
            else { return }
            
            self.devices = self.discoverySession.devices
            inputCameraParam.options = self.devices.compactMap( { $0.localizedName } )
        }
        
        self.wasDisconnectedObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main)
        { [weak self] notification in
            
            guard let self = self,
                  let inputCameraParam = self.inputCamera.parameter as? StringParameter
            else { return }
            
            self.devices = self.discoverySession.devices
            inputCameraParam.options = self.devices.compactMap( { $0.localizedName } )
        }
        
        self.devices = self.discoverySession.devices
        if let inputCameraParam = self.inputCamera.parameter as? StringParameter
        {
            inputCameraParam.options = self.devices.compactMap( { $0.localizedName } )
        }

    }
    
    override public func startExecution(renderer:GraphRenderer) throws
    {
        if self.captureSession.isRunning == false
        {
            self.captureSession.startRunning()
        }
    }
    
    override public func stopExecution(renderer:GraphRenderer) throws
    {
        if self.captureSession.isRunning
        {
            self.captureSession.stopRunning()
        }
    }
  
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        
        if self.inputCamera.valueDidChange
        {
            try updateCameraSession()
        }
        
        if self.captureDelegate.gotNewPixelBuffer,
           let pixelBuffer = self.captureDelegate.pixelBuffer
        {
            let image = try renderer.newImage(fromPixelBuffer: pixelBuffer)

            self.outputTexturePort.send( image )
            self.captureDelegate.gotNewPixelBuffer = false
        }
        
     }

    
    private static func videoSettings() -> [String : Any]
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
    
    private func updateCameraSession() throws
    {
        if let deviceLocalizedName = self.inputCamera.value
        {
            if let uniqueIDForDeviceWithMatchingName = self.devices.first(where: { $0.localizedName == deviceLocalizedName })?.uniqueID,
               let device = AVCaptureDevice.init(uniqueID: uniqueIDForDeviceWithMatchingName)
            {
                try self.setupCaptureSession(videoDevice: device)
            }
            else
            {
                self.outputTexturePort.send( nil )
                throw FabricError(.execution(.deviceNotFound),
                                  severity: .recoverable,
                                  message: "Camera device not found: \(deviceLocalizedName)")
            }
        }
    }
    
    private func setupCaptureSession(videoDevice:AVCaptureDevice) throws
    {
        if self.captureSession.isRunning
        {
            self.captureSession.stopRunning()
            
            self.captureSession.inputs.forEach { input in
                self.captureSession.removeInput(input)
            }
            
            self.captureSession.outputs.forEach { output in
                self.captureSession.removeOutput(output)
            }
        }

        let videoDeviceInput: AVCaptureDeviceInput
        do
        {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        }
        catch
        {
            throw FabricError(.execution(.deviceNotFound),
                              severity: .recoverable,
                              message: "Could not create camera input for \(videoDevice.localizedName)",
                              underlyingError: error)
        }

        guard self.captureSession.canAddInput(videoDeviceInput) else
        {
            throw FabricError(.execution(.deviceNotFound),
                              severity: .recoverable,
                              message: "Could not add camera input for \(videoDevice.localizedName)")
        }
        
        self.captureSession.beginConfiguration()
        
        self.captureSession.sessionPreset = .high

        self.captureSession.addInput(videoDeviceInput)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = Self.videoSettings()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self.captureDelegate, queue: self.captureDelegate.captureQueue)
        
        guard
            self.captureSession.canAddOutput(videoOutput)
        else
        {
            throw FabricError(.execution(.deviceNotFound),
                              severity: .recoverable,
                              message: "Could not add camera output for \(videoDevice.localizedName)")
        }

        self.captureSession.addOutput(videoOutput)
        self.captureSession.commitConfiguration()
        
        self.captureSession.startRunning()
        
    }
    
   
}
