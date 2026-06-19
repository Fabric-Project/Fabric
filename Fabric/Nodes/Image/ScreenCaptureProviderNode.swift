//
//  DisplacementMaterial.metal
//
//
//  Created by Anton Marini on 2/23/26.
//

#if os(macOS)

import Foundation
import Satin
import simd
import Metal
import CoreMedia
import ScreenCaptureKit

public class ScreenCaptureProviderNode: Node
{
    private enum CaptureKind: String
    {
        case display = "Display"
        case window = "Window"
        case application = "Application"
    }

    private enum CaptureTarget
    {
        case display(SCDisplay)
        case window(SCWindow)
        case application(SCRunningApplication)
    }

    private final class StreamOutputHandler: NSObject, SCStreamOutput, SCStreamDelegate
    {
        private let lock = NSLock()
        private var latestPixelBuffer: CVPixelBuffer? = nil

        func consumeLatestPixelBuffer() -> CVPixelBuffer?
        {
            lock.lock()
            defer { lock.unlock() }
            let pixelBuffer = latestPixelBuffer
            self.latestPixelBuffer = nil
            return pixelBuffer
        }

        func clear()
        {
            lock.lock()
            defer { lock.unlock() }
            self.latestPixelBuffer = nil
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType)
        {
            guard type == .screen,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else
            {
                return
            }

            lock.lock()
            self.latestPixelBuffer = pixelBuffer
            lock.unlock()
        }
    }

    public override class var name: String { "Screen Capture Provider" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Capture a display, window, or application and provide output Images" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputCaptureType", ParameterPort(parameter: StringParameter("Capture Type", CaptureKind.display.rawValue, [CaptureKind.display.rawValue, CaptureKind.window.rawValue, CaptureKind.application.rawValue], .dropdown, "Screen capture source type"))),
            ("inputCaptureSource", ParameterPort(parameter: StringParameter("Capture Source", "", [String](), .dropdown, "Display, window, or application to capture"))),
            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Current screen capture frame")),
        ]
    }

    public var inputCaptureType: ParameterPort<String> { port(named: "inputCaptureType") }
    public var inputCaptureSource: ParameterPort<String> { port(named: "inputCaptureSource") }
    public var outputTexturePort: NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private let streamOutputHandler = StreamOutputHandler()
    @ObservationIgnored private let sampleHandlerQueue = DispatchQueue(label: "fabric.ScreenCaptureProviderNode.sample_handler")
    @ObservationIgnored private var stream: SCStream? = nil
    @ObservationIgnored private var optionsToTargets: [String: CaptureTarget] = [:]
    @ObservationIgnored private var latestShareableContent: SCShareableContent? = nil
    @ObservationIgnored private var refreshTask: Task<Void, Never>? = nil
    @ObservationIgnored private var streamTask: Task<Void, Never>? = nil

    public required init(context: Context)
    {
        super.init(context: context)
        self.scheduleRefreshAndReconfigure()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.scheduleRefreshAndReconfigure()
    }

    override public func stopExecution(context: GraphExecutionContext)
    {
        self.stopStreamAndClear()
    }

    override public func teardown()
    {
        super.teardown()
        self.stopStreamAndClear()
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputCaptureType.valueDidChange || self.inputCaptureSource.valueDidChange
        {
            self.scheduleRefreshAndReconfigure()
        }

        if let pixelBuffer = streamOutputHandler.consumeLatestPixelBuffer(),
           let renderer = context.graphRenderer,
           let image = renderer.newImage(fromPixelBuffer: pixelBuffer)
        {
            self.outputTexturePort.send(image)
        }
    }

    private func scheduleRefreshAndReconfigure()
    {
        self.refreshTask?.cancel()
        self.refreshTask = Task { [weak self] in
            await self?.refreshTargetsAndReconfigure()
        }
    }

    @MainActor
    private func refreshTargetsAndReconfigure() async
    {
        do
        {
            let shareableContent = try await SCShareableContent.current
            let captureKind = self.currentCaptureKind()
            self.latestShareableContent = shareableContent

            self.optionsToTargets = self.makeOptions(shareableContent: shareableContent, captureKind: captureKind)

            let options = self.optionsToTargets.keys.sorted()
            if let sourceParameter = self.inputCaptureSource.parameter as? StringParameter
            {
                sourceParameter.options = options
            }

            let selectionIsValid = options.contains(self.inputCaptureSource.value ?? "")
            if !selectionIsValid
            {
                self.inputCaptureSource.value = options.first ?? ""
            }

            await self.reconfigureStream()
        }
        catch
        {
            self.outputTexturePort.send(nil)
            await self.stopStream()
        }
    }

    @MainActor
    private func reconfigureStream() async
    {
        let selection = self.inputCaptureSource.value ?? ""
        guard let target = self.optionsToTargets[selection]
        else
        {
            self.outputTexturePort.send(nil)
            await self.stopStream()
            return
        }

        self.streamTask?.cancel()
        self.streamTask = Task { [weak self] in
            guard let self else { return }
            await self.stopStream()
            await self.startStream(target: target)
        }
    }

    @MainActor
    private func startStream(target: CaptureTarget) async
    {
        guard let filter = self.contentFilter(for: target) else
        {
            self.outputTexturePort.send(nil)
            return
        }

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.queueDepth = 3

        streamConfiguration.showsCursor = false
        streamConfiguration.showMouseClicks = false

        let width = max(1, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        let height = max(1, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        streamConfiguration.width = width
        streamConfiguration.height = height

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: streamOutputHandler)

        do
        {
            try stream.addStreamOutput(streamOutputHandler, type: .screen, sampleHandlerQueue: sampleHandlerQueue)
            try await stream.startCapture()
            self.stream = stream
        }
        catch
        {
            self.stream = nil
            self.outputTexturePort.send(nil)
        }
    }

    @MainActor
    private func stopStream() async
    {
        guard let stream else
        {
            self.streamOutputHandler.clear()
            return
        }

        do
        {
            try await stream.stopCapture()
        }
        catch
        {
            // Swallow stop errors and ensure local teardown.
        }

        self.stream = nil
        self.streamOutputHandler.clear()
    }

    private func stopStreamAndClear()
    {
        self.refreshTask?.cancel()
        self.streamTask?.cancel()
        self.outputTexturePort.send(nil)

        Task { [weak self] in
            await self?.stopStream()
        }
    }

    @MainActor
    private func contentFilter(for target: CaptureTarget) -> SCContentFilter?
    {
        switch target
        {
        case .display(let display):
            return SCContentFilter(display: display, excludingWindows: [])

        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)

        case .application(let application):
            guard let displayTarget = self.latestShareableContent?.displays.first
            else
            {
                return nil
            }
            return SCContentFilter(display: displayTarget, including: [application], exceptingWindows: [])
        }
    }

    private func makeOptions(shareableContent: SCShareableContent, captureKind: CaptureKind) -> [String: CaptureTarget]
    {
        var result: [String: CaptureTarget] = [:]

        switch captureKind
        {
        case .display:
            for display in shareableContent.displays
            {
                let option = "Display \(display.displayID)"
                result[option] = .display(display)
            }

        case .window:
            let windows = shareableContent.windows.filter { $0.isOnScreen && $0.isActive && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier }
            for window in windows
            {
                let appName = window.owningApplication?.applicationName ?? "Unknown App"
                let title = (window.title?.isEmpty == false) ? window.title! : "Untitled"
                let option = "\(appName) - \(title)"
                result[option] = .window(window)
            }

        case .application:
            let applications = shareableContent.applications.filter { $0.processID != ProcessInfo.processInfo.processIdentifier }
            for application in applications
            {
                let option = "\(application.applicationName)"
                result[option] = .application(application)
            }
        }

        return result
    }

    private func currentCaptureKind() -> CaptureKind
    {
        guard let rawValue = self.inputCaptureType.value,
              let kind = CaptureKind(rawValue: rawValue)
        else
        {
            return .display
        }

        return kind
    }
}

#endif
