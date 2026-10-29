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
import SwiftUI
import os
import Synchronization

public class ScreenCaptureProviderNode: Node
{
    fileprivate static let log = Logger(subsystem: "graphics.fabric", category: "ScreenCaptureProviderNode")

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

    private final class StreamDelegate: NSObject, SCStreamOutput, SCStreamDelegate
    {
        // Written on the sample handler queue, taken by execute on the render thread.
        private let latestPixelBuffer = Mutex<CVPixelBuffer?>(nil)

        /// The newest frame since the last call, or nil when none has arrived.
        func takeLatestPixelBuffer() -> CVPixelBuffer?
        {
            self.latestPixelBuffer.withLock { latest in
                defer { latest = nil }
                return latest
            }
        }

        func clear()
        {
            self.latestPixelBuffer.withLock { $0 = nil }
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType)
        {
            guard type == .screen,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else
            {
                return
            }

            self.latestPixelBuffer.withLock { $0 = pixelBuffer }
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

    private let streamDelegate = StreamDelegate()
    private let sampleHandlerQueue = DispatchQueue(label: "fabric.ScreenCaptureProviderNode.sample_handler")
    private var stream: SCStream? = nil
    private var optionsToTargets: [String: CaptureTarget] = [:]
    private var latestShareableContent: SCShareableContent? = nil
    /// Set by start and Retry, which can run outside execution; execute restarts
    /// the capture.
    private let captureRestartRequested = Atomic<Bool>(false)
    /// Bumped by each restart and stop. A listing starts capture only if no
    /// restart or stop came after it.
    private let captureGeneration = Atomic<Int>(0)

    // MARK: - Capture Status

    /// Why a started node is not capturing, and whether Retry can help: a
    /// Screen Recording permission granted in System Settings only takes
    /// effect after a relaunch.
    private struct CaptureFailure: Equatable
    {
        let status: NodeStatus
        let canRetry: Bool
    }

    /// Main-actor state, set by the capture changes. Each failure is worded
    /// once, where it happens, so the glyph, the settings view and the log agree.
    private var captureFailure: CaptureFailure?
    {
        didSet
        {
            guard captureFailure != oldValue else { return }
            performOnMainSync
            {
                _settingsModelStorage?.captureStatus = captureFailure?.status
                _settingsModelStorage?.canRetry = captureFailure?.canRetry ?? false
            }
            self.subtitleSubject.send()
        }
    }

    override public func deriveStatuses() -> [NodeStatus] { captureFailure.map { [$0.status] } ?? [] }

    private func reportCaptureFailure(_ message: String?, canRetry: Bool = true)
    {
        if let message
        {
            Self.log.error("\(message, privacy: .public)")
        }
        self.captureFailure = message.map { CaptureFailure(status: .error($0), canRetry: canRetry) }
    }

    fileprivate func retryCapture()
    {
        self.captureRestartRequested.store(true, ordering: .relaxed)
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    @MainActor
    @Observable final class SettingsModel
    {
        /// Why the node is not capturing although it is started, or nil.
        var captureStatus: NodeStatus?
        var canRetry = false
        @ObservationIgnored private weak var node: ScreenCaptureProviderNode?

        init(node: ScreenCaptureProviderNode)
        {
            self.node = node
            self.captureStatus = node.captureFailure?.status
            self.canRetry = node.captureFailure?.canRetry ?? false
        }

        func retryCapture() { node?.retryCapture() }
    }

    private var _settingsModelStorage: SettingsModel? = nil

    override public func settingsView() -> AnyView
    {
        performOnMainSync
        {
            if _settingsModelStorage == nil { _settingsModelStorage = SettingsModel(node: self) }
            return AnyView(ScreenCaptureProviderNodeSettingsView(model: _settingsModelStorage!))
        }
    }

    override public var settingsSize: SettingsViewSize { .Small }

    public required init(context: Context)
    {
        super.init(context: context)
        self.listTargets(startingCaptureFor: nil)
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.listTargets(startingCaptureFor: nil)
    }

    override public func startExecution(renderer: GraphRenderer)
    throws
    {
        self.captureRestartRequested.store(true, ordering: .relaxed)
        try super.startExecution(renderer: renderer)
    }

    override public func stopExecution(renderer: GraphRenderer)
    throws
    {
        self.stopCapture()
        try super.stopExecution(renderer: renderer)
    }

    override public func teardown()
    {
        super.teardown()
        self.stopCapture()
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let sourceChanged = self.inputCaptureType.valueDidChange || self.inputCaptureSource.valueDidChange
        if self.captureRestartRequested.exchange(false, ordering: .relaxed) || sourceChanged
        {
            self.restartCapture()
        }

        if let pixelBuffer = streamDelegate.takeLatestPixelBuffer()
        {
            let image = try renderer.newImage(fromPixelBuffer: pixelBuffer)

            self.outputTexturePort.send(image)
        }
    }

    // MARK: - Capture

    /// Stops the stream, then lists the sources and starts the stream on main.
    private func restartCapture()
    {
        self.stopStream()
        let generation = self.captureGeneration.wrappingAdd(1, ordering: .relaxed).newValue
        self.listTargets(startingCaptureFor: generation)
    }

    private func stopCapture()
    {
        self.captureRestartRequested.store(false, ordering: .relaxed)
        self.captureGeneration.wrappingAdd(1, ordering: .relaxed)
        self.stopStream()
        self.outputTexturePort.send(nil)
        self.reportCaptureFailure(nil)
    }

    /// Lists the sources, then fills the dropdown on main. With a generation,
    /// it also starts capture, unless a restart or stop came after it.
    private func listTargets(startingCaptureFor generation: Int?)
    {
        Task
        {
            let listing: Result<SCShareableContent, any Error>
            do { listing = .success(try await SCShareableContent.current) }
            catch { listing = .failure(error) }

            self.performOnMainAsync
            {
                let startsCapture = generation == self.captureGeneration.load(ordering: .relaxed)
                switch listing
                {
                case .success(let shareableContent):
                    self.applyTargets(shareableContent)
                    if startsCapture { self.startStream() }

                case .failure(let error):
                    guard startsCapture else { return }
                    Self.log.error("Could not list capture sources: \(error, privacy: .public)")
                    self.outputTexturePort.send(nil)
                    self.reportCaptureFailure("Cannot list screens and windows: \(error.localizedDescription). If Screen Recording is not allowed, allow it in System Settings › Privacy & Security, then relaunch.",
                                              canRetry: false)
                }
            }
        }
    }

    /// Fills the source dropdown, and selects the first source when the selection is gone.
    private func applyTargets(_ shareableContent: SCShareableContent)
    {
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
    }

    private func startStream()
    {
        let selection = self.inputCaptureSource.value ?? ""
        guard let target = self.optionsToTargets[selection] else
        {
            self.reportCaptureFailure(selection.isEmpty ? "Nothing to capture." : "Capture source not found: \(selection).")
            self.outputTexturePort.send(nil)
            return
        }

        guard let filter = self.contentFilter(for: target) else
        {
            self.reportCaptureFailure("No display to capture the application on.")
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

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: streamDelegate)

        do
        {
            try stream.addStreamOutput(streamDelegate, type: .screen, sampleHandlerQueue: sampleHandlerQueue)
        }
        catch
        {
            self.reportCaptureFailure("Cannot start capture: \(error.localizedDescription)")
            self.outputTexturePort.send(nil)
            return
        }

        self.stream = stream
        self.reportCaptureFailure(nil)
        stream.startCapture { [weak self] error in
            guard let self else
            {
                if error == nil { stream.stopCapture() }
                return
            }
            self.performOnMainAsync {
                // A stop or restart while the stream was starting could not stop it,
                // so it stops here; its failure is no longer the node's state.
                guard self.stream === stream else
                {
                    if error == nil { stream.stopCapture() }
                    return
                }
                if let error
                {
                    self.reportCaptureFailure("Cannot start capture: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopStream()
    {
        if let stream
        {
            // Removing the output stops frames at once; stopping finishes later,
            // and the task holds the stream until it has.
            try? stream.removeStreamOutput(self.streamDelegate, type: .screen)
            Task { try? await stream.stopCapture() }
        }

        self.stream = nil
        self.streamDelegate.clear()
    }

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
                let windowTitle = (window.title?.isEmpty == false) ? window.title! : "Untitled"
                let option = "\(appName) - \(windowTitle)"
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


// MARK: - Settings View

private struct ScreenCaptureProviderNodeSettingsView: View
{
    let model: ScreenCaptureProviderNode.SettingsModel

    var body: some View
    {
        HStack
        {
            if let captureStatus = model.captureStatus
            {
                NodeStatusMessageView(status: captureStatus)
            }
            else
            {
                Text("Nothing to report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

#endif
