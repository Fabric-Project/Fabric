import Foundation
import Metal
import MetalPerformanceShaders
import Satin
@testable import Fabric

/// Measures any graph's rendering cost, from a document on disk or built in memory, writing TSV to `.build/benchmarks`.
/// A debug build runs a few frames, only to catch errors; its timings mean nothing. Run `swift test -c release -Xswiftc -enable-testing` for numbers.
/// Fails on errors, and never on a time: timings swing up to 2.5x between sessions, so compare builds A, B, A, B.
enum GraphBenchmark
{
    private static let renderSize = (width: 1920, height: 1080)
    private static let frameInterval: TimeInterval = 1.0 / 120.0
    #if DEBUG
    private static let configuration = "debug"
    private static let warmUpFrameCount = 5
    private static let measuredFrameCount = 10
    private static let gpuMeasuredFrameCount = 2
    private static let passCount = 1
    #else
    private static let configuration = "release"
    private static let warmUpFrameCount = 120
    private static let measuredFrameCount = 600
    private static let gpuMeasuredFrameCount = 120
    private static let passCount = 5
    #endif
    private static let minimumDrawnPixelCount = 100

    private static let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct FrameMeasurement
    {
        var renderThreadCPU: Double
        var processCPU: Double
        var wall: Double
    }

    private struct RenderTargets
    {
        let color: MTLTexture
        let depth: MTLTexture
        let stencil: MTLTexture
    }

    /// GPU times arrive on Metal's completion thread, one for each committed frame.
    private final class GPUTimes
    {
        private let lock = NSLock()
        private var milliseconds: [Double] = []
        private var failures: [String] = []

        func record(_ commandBuffer: MTLCommandBuffer)
        {
            let duration = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
            lock.withLock
            {
                if commandBuffer.status == .completed, duration > 0
                {
                    milliseconds.append(duration * 1000.0)
                }
                else
                {
                    failures.append("status \(commandBuffer.status.rawValue), duration \(duration), error \(String(describing: commandBuffer.error))")
                }
            }
        }

        func recordedFailures() -> [String] { lock.withLock { failures } }

        func take() -> [Double]
        {
            lock.withLock {
                defer { milliseconds.removeAll(keepingCapacity: true) }
                return milliseconds
            }
        }
    }

    /// The graph must use `context`. Writes `.build/benchmarks/<label>.tsv`.
    static func run(graph: Graph, label: String, context: Context) throws
    {
        try validateLoadedCleanly(graph)

        let errorDelegate = RecordingErrorDelegate()
        let renderer = GraphRenderer(context: context, graph: graph)
        renderer.errorDelegate = errorDelegate
        renderer.resize(size: (width: Float(Self.renderSize.width), height: Float(Self.renderSize.height)), scaleFactor: 1.0)
        try renderer.startExecution()
        defer
        {
            try? renderer.stopExecution()
            try? renderer.disableExecution()
            renderer.teardown()
        }

        let targets = try Self.makeRenderTargets(context: context)
        let renderPassDescriptor = Self.makeRenderPassDescriptor(targets: targets)
        // Offscreen command buffers are not bounded by a drawable, so the benchmark holds the app's limit itself.
        let framesInFlight = DispatchSemaphore(value: context.maxBuffersInFlight)
        let gpuTimes = GPUTimes()

        var nextFrameNumber = 0
        var report = Self.reportHeader(label: label, gpuName: context.device.name)
        var passMedians: [Double] = []

        for pass in 0..<Self.passCount
        {
            for _ in 0..<Self.warmUpFrameCount
            {
                _ = try Self.renderFrame(number: nextFrameNumber, renderer: renderer, renderPassDescriptor: renderPassDescriptor, framesInFlight: framesInFlight, gpuTimes: gpuTimes)
                nextFrameNumber += 1
            }
            Self.waitForGPU(framesInFlight: framesInFlight, limit: context.maxBuffersInFlight)
            _ = gpuTimes.take()

            if pass == 0
            {
                try Self.validateFirstRender(graph: graph, errorDelegate: errorDelegate, colorTexture: targets.color)
            }

            var measurements: [FrameMeasurement] = []
            measurements.reserveCapacity(Self.measuredFrameCount)
            for _ in 0..<Self.measuredFrameCount
            {
                measurements.append(try Self.renderFrame(number: nextFrameNumber, renderer: renderer, renderPassDescriptor: renderPassDescriptor, framesInFlight: framesInFlight, gpuTimes: gpuTimes))
                nextFrameNumber += 1
            }
            Self.waitForGPU(framesInFlight: framesInFlight, limit: context.maxBuffersInFlight)
            _ = gpuTimes.take()

            // One frame at a time: overlapping frames share the GPU, so their spans overstate each frame's cost.
            for _ in 0..<Self.gpuMeasuredFrameCount
            {
                _ = try Self.renderFrame(number: nextFrameNumber, renderer: renderer, renderPassDescriptor: renderPassDescriptor, framesInFlight: framesInFlight, gpuTimes: gpuTimes)
                nextFrameNumber += 1
                Self.waitForGPU(framesInFlight: framesInFlight, limit: context.maxBuffersInFlight)
            }

            let gpuMilliseconds = gpuTimes.take()
            let gpuFailures = gpuTimes.recordedFailures()
            guard gpuFailures.isEmpty, gpuMilliseconds.count == Self.gpuMeasuredFrameCount else
            {
                throw GraphExecutionTestFailure("GPU work failed: \(gpuFailures); \(gpuMilliseconds.count) of \(Self.gpuMeasuredFrameCount) frames timed")
            }

            let renderThreadCPU = measurements.map(\.renderThreadCPU)
            report += Self.reportRow(pass: pass, metric: "render_thread_cpu_ms", values: renderThreadCPU)
            report += Self.reportRow(pass: pass, metric: "process_cpu_ms", values: measurements.map(\.processCPU))
            report += Self.reportRow(pass: pass, metric: "wall_ms", values: measurements.map(\.wall))
            report += Self.reportRow(pass: pass, metric: "gpu_ms", values: gpuMilliseconds)
            report += "# pass_\(pass)_thermal_state\t\(ProcessInfo.processInfo.thermalState.rawValue)\n"
            passMedians.append(Self.percentile(renderThreadCPU, 0.5))
        }

        guard errorDelegate.reportedErrors.isEmpty else
        {
            throw GraphExecutionTestFailure("Rendering reported errors: \(errorDelegate.reportedErrors)")
        }

        let outputDirectory = repositoryRootURL.appending(path: ".build/benchmarks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appending(path: "\(label).tsv")
        try report.write(to: outputURL, atomically: true, encoding: .utf8)

        let medianMilliseconds = Self.percentile(passMedians, 0.5)
        let percentOfFrame = medianMilliseconds / (Self.frameInterval * 1000.0) * 100.0
        print("[GraphBenchmark] \(label) (\(configuration)): render thread CPU cost \(Self.formatted(medianMilliseconds)) ms/frame, \(Self.formatted(percentOfFrame))% of a 120 fps budget; results in \(outputURL.path)")
    }

    // MARK: - Rendering

    private static func renderFrame(number: Int,
                                    renderer: GraphRenderer,
                                    renderPassDescriptor: MTLRenderPassDescriptor,
                                    framesInFlight: DispatchSemaphore,
                                    gpuTimes: GPUTimes) throws -> FrameMeasurement
    {
        let wallStart = DispatchTime.now().uptimeNanoseconds
        let processStart = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)

        framesInFlight.wait()

        let threadStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)

        // Nothing else drains this thread's pool between frames, as a run loop does in the app.
        try autoreleasepool
        {
            guard let commandBuffer = renderer.makeCommandBuffer() as? MPSCommandBuffer else
            {
                framesInFlight.signal()
                throw GraphExecutionTestFailure("Failed to create a graph command buffer")
            }

            let time = TimeInterval(number) * frameInterval
            let timing = GraphExecutionTiming(time: time,
                                              deltaTime: frameInterval,
                                              displayTime: time,
                                              systemTime: time,
                                              hostMediaTime: time,
                                              frameNumber: number)
            try renderer.executeAndDraw(executionInfo: GraphExecutionInfo(timing: timing, iterationInfo: nil, eventInfo: nil),
                                        renderPassDescriptor: renderPassDescriptor,
                                        commandBuffer: commandBuffer)

            commandBuffer.rootCommandBuffer.addCompletedHandler
            { completed in
                gpuTimes.record(completed)
                framesInFlight.signal()
            }
            commandBuffer.commit()
        }

        let renderThreadNanoseconds = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - threadStart

        return FrameMeasurement(renderThreadCPU: Double(renderThreadNanoseconds) / 1_000_000.0,
                                processCPU: Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - processStart) / 1_000_000.0,
                                wall: Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1_000_000.0)
    }

    /// Returns once every frame in flight has completed, leaving all slots free.
    private static func waitForGPU(framesInFlight: DispatchSemaphore, limit: Int)
    {
        for _ in 0..<limit { framesInFlight.wait() }
        for _ in 0..<limit { framesInFlight.signal() }
    }

    // MARK: - Setup

    /// The context FabricDocument gives the editor.
    static func makeEditorContext() throws -> Context
    {
        guard let device = MTLCreateSystemDefaultDevice() else
        {
            throw GraphExecutionTestFailure("Metal is unavailable")
        }

        return Context(device: device,
                       sampleCount: 1,
                       colorPixelFormat: .rgba16Float,
                       depthPixelFormat: .depth32Float,
                       stencilPixelFormat: .stencil8,
                       alphaOitEnabled: true)
    }

    static func loadGraph(at documentURL: URL, context: Context) throws -> Graph
    {
        guard FileManager.default.fileExists(atPath: documentURL.path) else
        {
            throw GraphExecutionTestFailure("\(documentURL.path) is missing")
        }

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context,
                                         fileReferenceBaseURL: documentURL.deletingLastPathComponent())
        return try decoder.decode(Graph.self, from: Data(contentsOf: documentURL))
    }

    private static func validateLoadedCleanly(_ graph: Graph) throws
    {
        guard graph.missingNodeDiagnostics.isEmpty,
              graph.droppedPortStateDiagnostics.isEmpty,
              graph.droppedConnectionDiagnostics.isEmpty
        else
        {
            throw GraphExecutionTestFailure("The graph did not load cleanly")
        }

        for subgraphNode in graph.nodes.compactMap({ $0 as? SubgraphNode })
        {
            try validateLoadedCleanly(subgraphNode.subGraph)
        }
    }

    private static func nodeErrors(in graph: Graph) -> [NodeStatus]
    {
        graph.nodes.flatMap
        { node -> [NodeStatus] in
            let errors = node.deriveStatuses().filter { if case .error = $0 { true } else { false } }
            guard let subgraphNode = node as? SubgraphNode else { return errors }
            return errors + nodeErrors(in: subgraphNode.subGraph)
        }
    }

    private static func validateFirstRender(graph: Graph, errorDelegate: RecordingErrorDelegate, colorTexture: MTLTexture) throws
    {
        guard errorDelegate.reportedErrors.isEmpty else
        {
            throw GraphExecutionTestFailure("Rendering reported errors: \(errorDelegate.reportedErrors)")
        }

        let errors = nodeErrors(in: graph)
        guard errors.isEmpty else
        {
            throw GraphExecutionTestFailure("Nodes reported errors: \(errors)")
        }

        guard drawnPixelCount(in: colorTexture) >= minimumDrawnPixelCount else
        {
            throw GraphExecutionTestFailure("The frame is empty: nothing was drawn")
        }
    }

    /// Pixels that differ from the corner, which the scene leaves at the clear color or a uniform background.
    private static func drawnPixelCount(in texture: MTLTexture) -> Int
    {
        let channelsPerPixel = 4
        let bytesPerRow = texture.width * channelsPerPixel * MemoryLayout<UInt16>.stride
        var channels = [UInt16](repeating: 0, count: texture.width * texture.height * channelsPerPixel)
        channels.withUnsafeMutableBytes
        { bytes in
            if let baseAddress = bytes.baseAddress
            {
                texture.getBytes(baseAddress,
                                 bytesPerRow: bytesPerRow,
                                 from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                                 mipmapLevel: 0)
            }
        }

        let corner = channels[0..<channelsPerPixel]
        return stride(from: 0, to: channels.count, by: channelsPerPixel).count
        { pixelStart in
            !channels[pixelStart..<(pixelStart + channelsPerPixel)].elementsEqual(corner)
        }
    }

    private static func makeRenderTargets(context: Context) throws -> RenderTargets
    {
        func makeTexture(pixelFormat: MTLPixelFormat, storageMode: MTLStorageMode) throws -> MTLTexture
        {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                      width: renderSize.width,
                                                                      height: renderSize.height,
                                                                      mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = storageMode
            guard let texture = context.device.makeTexture(descriptor: descriptor) else
            {
                throw GraphExecutionTestFailure("Failed to create a \(pixelFormat) render target")
            }
            return texture
        }

        // Color is shared so the setup check can read it back.
        return RenderTargets(color: try makeTexture(pixelFormat: context.colorPixelFormat, storageMode: .shared),
                             depth: try makeTexture(pixelFormat: context.depthPixelFormat, storageMode: .private),
                             stencil: try makeTexture(pixelFormat: context.stencilPixelFormat, storageMode: .private))
    }

    private static func makeRenderPassDescriptor(targets: RenderTargets) -> MTLRenderPassDescriptor
    {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = targets.color
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = targets.depth
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.stencilAttachment.texture = targets.stencil
        descriptor.stencilAttachment.loadAction = .clear
        descriptor.stencilAttachment.storeAction = .dontCare
        descriptor.renderTargetWidth = renderSize.width
        descriptor.renderTargetHeight = renderSize.height
        return descriptor
    }

    // MARK: - Report

    private static func reportHeader(label: String, gpuName: String) -> String
    {
        let processInfo = ProcessInfo.processInfo
        let metadata = [
            "fabric\t\(revision(of: repositoryRootURL))",
            "satin\t\(revision(of: repositoryRootURL.appending(path: "Satin")))",
            "fabric_samples\t\(revision(of: repositoryRootURL.appending(path: "Fabric-Samples")))",
            "machine\t\(machineModel())",
            "gpu\t\(gpuName)",
            "os\t\(processInfo.operatingSystemVersionString)",
            "configuration\t\(configuration)",
            "thermal_state\t\(processInfo.thermalState.rawValue)",
            "low_power_mode\t\(processInfo.isLowPowerModeEnabled)",
            "graph\t\(label)",
            "render_size\t\(renderSize.width)x\(renderSize.height)",
            "frames_per_pass\t\(measuredFrameCount)",
            "gpu_frames_per_pass\t\(gpuMeasuredFrameCount)",
        ]
        return metadata.map { "# \($0)\n" }.joined() + "pass\tmetric\tmedian\tp95\n"
    }

    private static func reportRow(pass: Int, metric: String, values: [Double]) -> String
    {
        "\(pass)\t\(metric)\t\(formatted(percentile(values, 0.5)))\t\(formatted(percentile(values, 0.95)))\n"
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double
    {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }

    private static func formatted(_ value: Double) -> String
    {
        value.formatted(.number.precision(.fractionLength(3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func revision(of repositoryURL: URL) -> String
    {
        let revision = gitOutput(["rev-parse", "--short=12", "HEAD"], in: repositoryURL)
        let changes = gitOutput(["status", "--porcelain", "--untracked-files=no"], in: repositoryURL)
        return changes.isEmpty ? revision : "\(revision)-dirty"
    }

    private static func gitOutput(_ arguments: [String], in repositoryURL: URL) -> String
    {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", repositoryURL.path] + arguments
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "unknown" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func machineModel() -> String
    {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
