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

    private let streamOutputHandler = StreamOutputHandler()
    private let sampleHandlerQueue = DispatchQueue(label: "fabric.ScreenCaptureProviderNode.sample_handler")
    private var stream: SCStream? = nil
    private var optionsToTargets: [String: CaptureTarget] = [:]
    private var latestShareableContent: SCShareableContent? = nil
    // Capture changes run one at a time on the main actor, each after the one
    // before it, so a stop is never overtaken by a start still in flight.
    private var captureChangeTask: Task<Void, Never>? = nil

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
            _settingsModelStorage?.captureStatus = captureFailure?.status
            _settingsModelStorage?.canRetry = captureFailure?.canRetry ?? false
            self.subtitleSubject.send()
        }
    }

    override public func deriveStatuses() -> [NodeStatus] { captureFailure.map { [$0.status] } ?? [] }

    @MainActor
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
        self.enqueueCaptureRestart()
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

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
        if _settingsModelStorage == nil { _settingsModelStorage = SettingsModel(node: self) }
        return AnyView(ScreenCaptureProviderNodeSettingsView(model: _settingsModelStorage!))
    }

    override public var settingsSize: SettingsViewSize { .Small }

    public required init(context: Context)
    {
        super.init(context: context)
        self.enqueueCaptureChange { await $0.refreshTargets() }
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.enqueueCaptureChange { await $0.refreshTargets() }
    }

    override public func startExecution(renderer: GraphRenderer)
    throws
    {
        self.enqueueCaptureRestart()
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
        if self.inputCaptureType.valueDidChange || self.inputCaptureSource.valueDidChange
        {
            self.enqueueCaptureRestart()
        }

        if let pixelBuffer = streamOutputHandler.consumeLatestPixelBuffer()
        {
            let image = try renderer.newImage(fromPixelBuffer: pixelBuffer)

            self.outputTexturePort.send(image)
        }
    }

    /// A change that is superseded is cancelled, and still finishes before the next one runs.
    private func enqueueCaptureChange(_ change: @escaping @MainActor (ScreenCaptureProviderNode) async -> Void)
    {
        let previousChange = self.captureChangeTask
        previousChange?.cancel()
        self.captureChangeTask = Task { @MainActor [weak self] in
            await previousChange?.value
            guard let self else { return }
            await change(self)
        }
    }

    private func enqueueCaptureRestart()
    {
        self.enqueueCaptureChange { node in
            if let listingError = await node.refreshTargets()
            {
                await node.stopStream()
                node.outputTexturePort.send(nil)
                node.reportCaptureFailure("Cannot list screens and windows: \(listingError.localizedDescription). If Screen Recording is not allowed, allow it in System Settings › Privacy & Security, then relaunch.",
                                          canRetry: false)
                return
            }
            guard !Task.isCancelled else { return }
            await node.restartStream()
        }
    }

    private func stopCapture()
    {
        self.outputTexturePort.send(nil)
        self.enqueueCaptureChange { node in
            await node.stopStream()
            node.reportCaptureFailure(nil)
        }
    }

    /// Lists the sources for the dropdown; returns the error if they cannot be listed.
    @MainActor
    @discardableResult
    private func refreshTargets() async -> (any Error)?
    {
        let shareableContent: SCShareableContent
        do
        {
            shareableContent = try await SCShareableContent.current
        }
        catch
        {
            Self.log.error("Could not list capture sources: \(error, privacy: .public)")
            return error
        }

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
        return nil
    }

    @MainActor
    private func restartStream() async
    {
        await self.stopStream()

        let selection = self.inputCaptureSource.value ?? ""
        guard let target = self.optionsToTargets[selection] else
        {
            self.reportCaptureFailure(selection.isEmpty ? "Nothing to capture." : "Capture source not found: \(selection).")
            self.outputTexturePort.send(nil)
            return
        }

        await self.startStream(target: target)
    }

    @MainActor
    private func startStream(target: CaptureTarget) async
    {
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

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: streamOutputHandler)

        do
        {
            try stream.addStreamOutput(streamOutputHandler, type: .screen, sampleHandlerQueue: sampleHandlerQueue)
            try await stream.startCapture()
            self.stream = stream
            self.reportCaptureFailure(nil)
        }
        catch
        {
            self.reportCaptureFailure("Cannot start capture: \(error.localizedDescription)")
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
                    .font(.system(size: 10))
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
