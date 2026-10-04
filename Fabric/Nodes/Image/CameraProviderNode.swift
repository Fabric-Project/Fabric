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
import SwiftUI
import os
import Synchronization
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

    
    let screenCaptureProperty = CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices)
    let wirelessCaptureProperty = CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices)
    let globalScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)
    let mainElement = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    
    var property = CMIOObjectPropertyAddress(mSelector: screenCaptureProperty, mScope: globalScope, mElement:mainElement )

    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, UInt32(sizeOfAllow), &allow)

    property = CMIOObjectPropertyAddress(mSelector: wirelessCaptureProperty, mScope: globalScope, mElement: mainElement)

    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, UInt32(sizeOfAllow), &allow)
    #endif
}()

public class CameraProviderNode : Node
{
    fileprivate static let log = Logger(subsystem: "graphics.fabric", category: "CameraProviderNode")

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
    
    // Written on the main queue and at enable, read by execute on the render thread.
    private let devices = Mutex<[AVCaptureDevice]>([])

    // Asks execute to build the session: after enable, since disable releases
    // it, and once camera access or a device arrives. Set from the permission
    // callback too; a set that lands after a stop does nothing, as only started
    // nodes execute.
    private let captureSessionNeedsSetup = Atomic<Bool>(false)

    private var wasConnectedObserver:Any? = nil
    private var wasDisconnectedObserver:Any? = nil

    required public init(context:Context)
    {
        // Forces the initialization when the class is accessed
        _ = CameraProviderNodeInitializer
        
        self.captureSession = AVCaptureSession()

        super.init(context: context)
    }
    
    
    required public init(from decoder: any Decoder) throws
    {
        // Forces the initialization when the class is accessed
        _ = CameraProviderNodeInitializer
        
        self.captureSession = AVCaptureSession()
                
        try super.init(from:decoder)
    }

    override public func enableExecution(renderer:GraphRenderer) throws
    {
        self.wasConnectedObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main)
        { [weak self] _ in
            guard let self else { return }
            self.refreshDevices()

            // A device arriving may be what a failed capture was waiting for.
            if self.captureStatus != nil
            {
                self.captureSessionNeedsSetup.store(true, ordering: .relaxed)
            }
        }

        self.wasDisconnectedObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main)
        { [weak self] _ in
            self?.refreshDevices()
        }

        self.refreshDevices()
        self.captureSessionNeedsSetup.store(true, ordering: .relaxed)
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer:GraphRenderer) throws
    {
        if let observer = self.wasConnectedObserver    { NotificationCenter.default.removeObserver(observer) }
        if let observer = self.wasDisconnectedObserver { NotificationCenter.default.removeObserver(observer) }
        self.wasConnectedObserver = nil
        self.wasDisconnectedObserver = nil

        // Stop has already stopped it; this lets its device input and output go.
        self.captureSession = AVCaptureSession()
        try super.disableExecution(renderer: renderer)
    }

    private func refreshDevices()
    {
        let fresh = self.discoverySession.devices
        self.devices.withLock { $0 = fresh }

        // Enable can run on the render thread; parameter options are observable, main-thread state.
        let names = fresh.map(\.localizedName)
        DispatchQueue.main.async { [weak self] in
            (self?.inputCamera.parameter as? StringParameter)?.options = names
        }
    }
    
    // Without camera access the node still starts, and outputs nothing.
    override public func startExecution(renderer:GraphRenderer) throws
    {
        DispatchQueue.main.async { [weak self] in self?.isRunning = true }
        self.requestCapture()
        // Stop cleared the status, so a session that could not be built is built
        // again, and reports again. Execute builds only with access.
        self.captureSessionNeedsSetup.store(true, ordering: .relaxed)
        if self.captureSession.isRunning == false
        {
            self.captureSession.startRunning()
        }
        try super.startExecution(renderer: renderer)
    }

    /// Asks for camera access if it has not been decided, and reports it if refused.
    private func requestCapture()
    {
        switch AVCaptureDevice.authorizationStatus(for: .video)
        {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else
                {
                    self?.reportCaptureStatus(Self.cameraAccessStatus)
                    return
                }
                self?.captureSessionNeedsSetup.store(true, ordering: .relaxed)
            }
        default:
            self.reportCaptureStatus(Self.cameraAccessStatus)
        }
    }

    private static let cameraAccessStatus = NodeStatus.error("Camera access is not allowed. Allow it in System Settings › Privacy & Security › Camera, then Retry.")

    fileprivate func retryCapture()
    {
        self.requestCapture()
        self.captureSessionNeedsSetup.store(true, ordering: .relaxed)
    }

    // MARK: - Capture Status

    // The status is main-thread state, read by the title and settings views.
    // Start, stop and execute can run on the render thread, and the permission
    // callback on any thread, so each hands over to main; the main queue keeps
    // them in order.
    private var isRunning = false

    /// Set while the node is started but not capturing. Each failure is worded
    /// once, where it happens, so the glyph, the settings view and the log agree.
    private var captureStatus: NodeStatus?
    {
        didSet
        {
            guard captureStatus != oldValue else { return }
            _settingsModelStorage?.captureFailure = captureStatus?.message
            // Retry is for failures; a warning, such as no camera selected, has nothing to retry.
            _settingsModelStorage?.canRetry = if case .error = captureStatus { true } else { false }
            self.subtitleSubject.send()
        }
    }

    override public func deriveStatuses() -> [NodeStatus] { captureStatus.map { [$0] } ?? [] }

    private func reportCaptureStatus(_ status: NodeStatus?)
    {
        if let status
        {
            Self.log.error("\(status.message, privacy: .public)")
        }
        DispatchQueue.main.async { [weak self] in
            // A failure reported after a stop is no longer the node's state.
            guard let self, self.isRunning else { return }
            self.captureStatus = status
        }
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    @Observable final class SettingsModel
    {
        /// Why the node is not capturing although it is started, or nil.
        var captureFailure: String?
        var canRetry = false
        @ObservationIgnored private weak var node: CameraProviderNode?

        init(node: CameraProviderNode)
        {
            self.node = node
            self.captureFailure = node.captureStatus?.message
            self.canRetry = if case .error = node.captureStatus { true } else { false }
        }

        func retryCapture() { node?.retryCapture() }
    }

    private var _settingsModelStorage: SettingsModel? = nil

    override public func settingsView() -> AnyView
    {
        if _settingsModelStorage == nil { _settingsModelStorage = SettingsModel(node: self) }
        return AnyView(CameraProviderNodeSettingsView(model: _settingsModelStorage!))
    }

    override public var settingsSize: SettingsViewSize { .Small }

    override public func stopExecution(renderer:GraphRenderer) throws
    {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.captureStatus = nil
        }
        if self.captureSession.isRunning
        {
            self.captureSession.stopRunning()
        }
        try super.stopExecution(renderer: renderer)
    }
  
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        
        let setupRequested = self.captureSessionNeedsSetup.exchange(false, ordering: .relaxed)
        if self.inputCamera.valueDidChange || setupRequested,
           AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        {
            do
            {
                try updateCameraSession()
            }
            catch
            {
                self.reportCaptureStatus(.error(error.localizedDescription))
                throw error
            }
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
        guard let deviceLocalizedName = self.inputCamera.value, !deviceLocalizedName.isEmpty else
        {
            self.outputTexturePort.send( nil )
            self.reportCaptureStatus(.warning("No camera is selected."))
            return
        }

        let knownDevices = self.devices.withLock { $0 }
        if let uniqueIDForDeviceWithMatchingName = knownDevices.first(where: { $0.localizedName == deviceLocalizedName })?.uniqueID,
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
        self.reportCaptureStatus(nil)
    }
    
   
}

// MARK: - Settings View

private struct CameraProviderNodeSettingsView: View
{
    let model: CameraProviderNode.SettingsModel

    var body: some View
    {
        HStack
        {
            Text(model.captureFailure ?? "Nothing to report.")
                .font(.system(size: 10))
                .foregroundStyle(model.captureFailure == nil ? .secondary : Color.red)

            Spacer()

            if model.canRetry
            {
                Button("Retry")
                {
                    model.retryCapture()
                }
                .controlSize(.small)
            }
        }
    }
}
