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
    
    @ObservationIgnored private let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external,], mediaType: nil, position:.unspecified)
    @ObservationIgnored private var device: AVCaptureDevice? = nil
    @ObservationIgnored private var captureSession: AVCaptureSession
    @ObservationIgnored private let captureDelegate = CaptureDelegate()

    @ObservationIgnored private var textureCache:CVMetalTextureCache?
    @ObservationIgnored private var observer: Any? = nil
    
    @ObservationIgnored private var devices = [AVCaptureDevice]()

    @ObservationIgnored private var wasConnectedObserver:Any? = nil
    @ObservationIgnored private var wasDisconnectedObserver:Any? = nil

    required public init(context:Context)
    {
        // Forces the initialization when the class is accessed
        _ = CameraProviderNodeInitializer
        
        self.captureSession = AVCaptureSession()

        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                                nil,
                                                context.device,
                                                nil,
                                                &self.textureCache)

        super.init(context: context)
        
        self.commonPostSetup()
    }
    
    
    required public init(from decoder: any Decoder) throws
    {
        // Forces the initialization when the class is accessed
        _ = CameraProviderNodeInitializer
        
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.captureSession = AVCaptureSession()
        
        let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                          nil,
                                          decodeContext.documentContext.device,
                                          nil,
                                          &self.textureCache)
        
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
    
  
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        
        if self.inputCamera.valueDidChange
        {
            updateCameraSession()
        }
        
       
        if let pixelBuffer = self.captureDelegate.pixelBuffer
        {
                CVMetalTextureCacheFlush(self.textureCache!, 0)
                
                var texture:CVMetalTexture? = nil
                
                let success = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                        self.textureCache!,
                                                                        pixelBuffer,
                                                                        nil,
                                                                        .bgra8Unorm,
                                                                        CVPixelBufferGetWidth(pixelBuffer),
                                                                        CVPixelBufferGetHeight(pixelBuffer),
                                                                        0,
                                                                        &texture)
                
                if success == kCVReturnSuccess && texture != nil
                {
                    let latestFrameTexture = CVMetalTextureGetTexture(texture!)!
                    
                    self.outputTexturePort.send( FabricImage.unmanaged(texture: latestFrameTexture) )
                }
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
    
    private func updateCameraSession()
    {
        if let deviceLocalizedName = self.inputCamera.value
        {
            if let uniqueIDForDeviceWithMatchingName = self.devices.first(where: { $0.localizedName == deviceLocalizedName })?.uniqueID,
               let device = AVCaptureDevice.init(uniqueID: uniqueIDForDeviceWithMatchingName)
            {
                self.setupCaptureSession(videoDevice: device)
            }
            else
            {
                self.outputTexturePort.send( nil )
                
                print("wtf")
            }
        }
    }
    
    private func setupCaptureSession(videoDevice:AVCaptureDevice)
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

        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
            self.captureSession.canAddInput(videoDeviceInput)
        else
        {
            print("Error: Could not create video device input.")
            return
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
            print("Error: Could not add video output.")
            return
        }

        self.captureSession.addOutput(videoOutput)
        self.captureSession.commitConfiguration()
        
        self.captureSession.startRunning()
        
    }
    
   
}
