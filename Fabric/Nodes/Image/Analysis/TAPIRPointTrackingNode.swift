//
//  TAPIRPointTrackingNode.swift
//  Fabric
//

import Foundation
import Metal
import MetalPerformanceShaders
import MPSMediaPipe
import MPSTAPNextPlusPlus
import Satin
import simd
import SwiftUI

public struct TAPIRPointTrackingSettings: Codable, Equatable
{
    public var pointCapacity: Int
    public var refinementCount: Int

    public init(
        pointCapacity: Int = 32,
        refinementCount: Int = 1
    )
    {
        self.pointCapacity = pointCapacity
        self.refinementCount = refinementCount
    }
}

/// Tracks caller-supplied points through a video stream using DeepMind's
/// causal BootsTAPIR model. Synchronous (the default Inference setting):
/// preprocessing, inference, recurrent-state updates and result copies go on
/// the node's own command buffer, which it commits and waits on, so results
/// belong to the current frame. Asynchronous: the same work is encoded onto
/// Fabric's shared MPSCommandBuffer, the node never commits or waits, and
/// numerical outputs are published after GPU completion, so they lag the
/// image stream.
public final class TAPIRPointTrackingNode: Node
{
    override public class var name: String { "MPS TAPIR Point Tracking" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Tracks points with the 256×256 causal BootsTAPIR model. Asynchronous inference encodes on Fabric's shared MPS command buffer and results lag a frame; Synchronous waits for them in the same frame. Point changes or Reset initialize a new tracking sequence."
    }

    private static let modelSize: Float = 256
    private static let pointCapacityOptions = ["1", "8", "16", "32", "64", "128", "256"]
    private static let refinementOptions = ["1", "2", "3", "4"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputImage", NodePort<FabricImage>(
                name: "Image",
                kind: .Inlet,
                description: "Video frame to track, stretched to TAPIR's fixed 256×256 input"
            )),
            ("inputQueryPoints", NodePort<ContiguousArray<simd_float2>>(
                name: "Query Points",
                kind: .Inlet,
                description: "Points to initialize in Fabric unit coordinates (-1...1 horizontally, aspect-scaled vertically). Changing the array starts a new tracking sequence."
            )),
            ("inputReset", ParameterPort(parameter: BoolParameter(
                "Reset",
                false,
                .button,
                "Reinitialize the current query points on the next image"
            ))),
            ("outputTrackedPoints", NodePort<ContiguousArray<simd_float2>>(
                name: "Points",
                kind: .Outlet,
                description: "Latest completed tracks in Fabric unit coordinates, index-aligned with Query Points"
            )),
            ("outputVisible", NodePort<ContiguousArray<Bool>>(
                name: "Visible",
                kind: .Outlet,
                description: "Per-point TAPIR visibility classification"
            )),
            ("outputVisibilityConfidence", NodePort<ContiguousArray<Float>>(
                name: "Confidence",
                kind: .Outlet,
                description: "Per-point sigmoid(-occlusion) × sigmoid(-expected-distance) confidence"
            )),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputQueryPoints: NodePort<ContiguousArray<simd_float2>> { port(named: "inputQueryPoints") }
    public var inputReset: ParameterPort<Bool> { port(named: "inputReset") }
    public var outputTrackedPoints: NodePort<ContiguousArray<simd_float2>> { port(named: "outputTrackedPoints") }
    public var outputVisible: NodePort<ContiguousArray<Bool>> { port(named: "outputVisible") }
    public var outputVisibilityConfidence: NodePort<ContiguousArray<Float>> { port(named: "outputVisibilityConfidence") }

    private struct PreparedConfiguration: Equatable
    {
        let pointCapacity: Int
        let refinementCount: Int
        let computePrecision: TAPIRComputePrecision
        let computeUnits: TAPIRComputeUnits
    }

    private struct CompletedResult
    {
        let points: ContiguousArray<simd_float2>
        let visible: ContiguousArray<Bool>
        let visibilityConfidence: ContiguousArray<Float>
    }

    private final class ReadbackSlot
    {
        let buffer: MTLBuffer
        private let lock = NSLock()
        private var inUse = false

        init(buffer: MTLBuffer) { self.buffer = buffer }

        func acquire() -> Bool
        {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.inUse else { return false }
            self.inUse = true
            return true
        }

        func release()
        {
            self.lock.lock()
            self.inUse = false
            self.lock.unlock()
        }
    }

    private var preparedConfiguration: PreparedConfiguration?
    private var preprocessor: MediaPipeCropPreprocessor?
    private var model: TAPIROnlineModel?
    private var sequenceInputs: TAPIRSequenceInputs?
    private var currentState: TAPIRCausalState?
    private var modelOutputs: [TAPIROnlineOutput] = []
    private var nextModelOutputIndex = 0
    private var readbackSlots: [ReadbackSlot] = []
    private var activeQueryPoints: ContiguousArray<simd_float2> = []
    private var activePresentationAspect: Float?
    private var sequenceGeneration = 0
    private var lastResetValue = false

    private let completedResultLock = NSLock()
    private var completedResult: CompletedResult?

    public private(set) var modelSettings: TAPIRPointTrackingSettings
    public private(set) var modelPrecision: MPSModelPrecision
    public private(set) var modelComputeUnits: MPSModelComputeUnits = .gpuAndNeuralEngine
    public private(set) var inferenceTiming: MPSInferenceTiming = .synchronous
    private var executionEnabled = false

    private enum ModelSettingsCodingKeys: String, CodingKey
    {
        case modelSettings
        case modelPrecision
        case modelComputeUnits
        case inferenceTiming
    }

    public required init(context: Context)
    {
        self.modelSettings = .init()
        self.modelPrecision = .highQuality
        super.init(context: context)
    }

    public init(context: Context, modelSettings: TAPIRPointTrackingSettings, modelPrecision: MPSModelPrecision = .highQuality, modelComputeUnits: MPSModelComputeUnits = .gpuAndNeuralEngine, inferenceTiming: MPSInferenceTiming = .synchronous)
    {
        self.modelSettings = modelSettings
        self.modelPrecision = modelPrecision
        self.modelComputeUnits = modelComputeUnits
        self.inferenceTiming = inferenceTiming
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: ModelSettingsCodingKeys.self)
        if let decoded = try container.decodeIfPresent(TAPIRPointTrackingSettings.self, forKey: .modelSettings)
        {
            self.modelSettings = decoded
        }
        else
        {
            self.modelSettings = TAPIRPointTrackingSettings(
                pointCapacity: Int(LegacyModelConfigurationPort.string(named: "inputPointCapacity", from: decoder) ?? "32") ?? 32,
                refinementCount: Int(LegacyModelConfigurationPort.string(named: "inputRefinementCount", from: decoder) ?? "1") ?? 1
            )
        }
        self.modelPrecision = try container.decodeIfPresent(MPSModelPrecision.self, forKey: .modelPrecision) ?? .highQuality
        self.modelComputeUnits = try container.decodeIfPresent(MPSModelComputeUnits.self, forKey: .modelComputeUnits) ?? .gpuAndNeuralEngine
        self.inferenceTiming = try container.decodeIfPresent(MPSInferenceTiming.self, forKey: .inferenceTiming) ?? .synchronous
        try super.init(from: decoder)
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: ModelSettingsCodingKeys.self)
        try container.encode(self.modelSettings, forKey: .modelSettings)
        try container.encode(self.modelPrecision, forKey: .modelPrecision)
        try container.encode(self.modelComputeUnits, forKey: .modelComputeUnits)
        try container.encode(self.inferenceTiming, forKey: .inferenceTiming)
    }

    override public func providesSettingsView() -> Bool { true }
    override public var settingsSize: SettingsViewSize { .Small }

    override public func settingsView() -> AnyView
    {
        AnyView(MPSModelConfigurationSettingsView(options: [
            MPSModelConfigurationOption(
                label: "Point Capacity",
                choices: Self.pointCapacityOptions,
                selection: Binding(
                    get: { [weak self] in String(self?.modelSettings.pointCapacity ?? 32) },
                    set: { [weak self] value in
                        guard let self, let pointCapacity = Int(value) else { return }
                        var settings = self.modelSettings
                        settings.pointCapacity = pointCapacity
                        self.apply(modelSettings: settings, modelPrecision: self.modelPrecision, modelComputeUnits: self.modelComputeUnits)
                    }
                )
            ),
            MPSModelConfigurationOption(
                label: "Refinement Passes",
                choices: Self.refinementOptions,
                selection: Binding(
                    get: { [weak self] in String(self?.modelSettings.refinementCount ?? 1) },
                    set: { [weak self] value in
                        guard let self, let refinementCount = Int(value) else { return }
                        var settings = self.modelSettings
                        settings.refinementCount = refinementCount
                        self.apply(modelSettings: settings, modelPrecision: self.modelPrecision, modelComputeUnits: self.modelComputeUnits)
                    }
                )
            ),
            MPSModelConfigurationOption(
                label: "Precision",
                choices: MPSModelPrecision.labels,
                selection: Binding(
                    get: { [weak self] in (self?.modelPrecision ?? .highQuality).label },
                    set: { [weak self] value in
                        guard let self, let precision = MPSModelPrecision(label: value) else { return }
                        self.apply(modelSettings: self.modelSettings, modelPrecision: precision, modelComputeUnits: self.modelComputeUnits)
                    }
                )
            ),
            MPSModelConfigurationOption(
                label: "Compute",
                choices: MPSModelComputeUnits.labels,
                selection: Binding(
                    get: { [weak self] in (self?.modelComputeUnits ?? .gpuAndNeuralEngine).label },
                    set: { [weak self] value in
                        guard let self, let computeUnits = MPSModelComputeUnits(label: value) else { return }
                        self.apply(modelSettings: self.modelSettings, modelPrecision: self.modelPrecision, modelComputeUnits: computeUnits)
                    }
                )
            ),
            MPSModelConfigurationOption(
                label: "Inference",
                choices: MPSInferenceTiming.labels,
                selection: Binding(
                    get: { [weak self] in (self?.inferenceTiming ?? .synchronous).label },
                    set: { [weak self] value in
                        guard let self, let inferenceTiming = MPSInferenceTiming(label: value) else { return }
                        self.apply(inferenceTiming: inferenceTiming)
                    }
                )
            ),
        ]))
    }

    override public func enableExecution(renderer: GraphRenderer) throws
    {
        try self.prepareModel(self.requestedConfiguration(for: self.modelSettings, precision: self.modelPrecision, computeUnits: self.modelComputeUnits))
        self.executionEnabled = true
        try super.enableExecution(renderer: renderer)
    }

    override public func disableExecution(renderer: GraphRenderer) throws
    {
        self.executionEnabled = false
        self.invalidatePreparedModel()
        self.clearPublishedResults()
        try super.disableExecution(renderer: renderer)
    }

    override public func stopExecution(renderer: GraphRenderer) throws
    {
        self.resetSequence()
        self.clearPublishedResults()
        try super.stopExecution(renderer: renderer)
    }

    override public func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        self.publishLatestCompletedResult()

        let resetValue = self.inputReset.value ?? false
        let resetTriggered = resetValue && !self.lastResetValue
        self.lastResetValue = resetValue

        guard self.inputImage.valueDidChange || self.inputQueryPoints.valueDidChange || resetTriggered || self.isDirty else { return }
        guard let image = self.inputImage.value else
        {
            self.clearPublishedResults()
            return
        }

        let queryPoints = self.inputQueryPoints.value ?? []
        guard !queryPoints.isEmpty else
        {
            self.resetSequence()
            self.clearPublishedResults()
            return
        }

        let configuration = self.requestedConfiguration(for: self.modelSettings, precision: self.modelPrecision, computeUnits: self.modelComputeUnits)
        try self.prepareModel(configuration)
        guard let model, let preprocessor else
        {
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "TAPIR model is unavailable")
        }
        // Synchronous, as in the MediaPipe nodes: this frame's crop, inference
        // and readback go on the node's own command buffer, which is committed
        // and waited on below, so results belong to this frame. Inside an
        // Iterator every iteration needs its own result, so it is always used.
        let synchronous = self.inferenceTiming == .synchronous || executionInfo.iterationInfo != nil
        let targetBuffer: MPSCommandBuffer
        if synchronous
        {
            guard let dedicated = self.context.commandQueue.makeCommandBuffer() else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create synchronous TAPIR command buffer")
            }
            targetBuffer = MPSCommandBuffer(commandBuffer: dedicated)
        }
        else
        {
            guard let frameCommandBuffer = commandBuffer as? MPSCommandBuffer else
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "TAPIR requires Fabric's shared MPSCommandBuffer")
            }
            targetBuffer = frameCommandBuffer
        }

        let boundedPoints = ContiguousArray(queryPoints.prefix(configuration.pointCapacity))
        let presentationAspect = Float(image.presentationSize.height / image.presentationSize.width)
        let mustResetSequence = resetTriggered
            || self.sequenceInputs == nil
            || boundedPoints != self.activeQueryPoints
            || presentationAspect != self.activePresentationAspect
        if mustResetSequence
        {
            try self.beginSequence(points: boundedPoints, image: image, model: model, pointCapacity: configuration.pointCapacity)
        }

        guard let sequenceInputs, let currentState, !self.modelOutputs.isEmpty else { return }
        let output = self.modelOutputs[self.nextModelOutputIndex]
        self.nextModelOutputIndex = (self.nextModelOutputIndex + 1) % self.modelOutputs.count
        let resetBuffer = mustResetSequence ? sequenceInputs.resetValueBuffer : sequenceInputs.continueValueBuffer

        commandBuffer.pushDebugGroup("MPS TAPIR Point Tracking")
        defer { commandBuffer.popDebugGroup() }

        let inputBuffer = try preprocessor.encode(
            texture: image.texture,
            textureTransform: image.textureTransform,
            centerNormalizedBottomLeft: simd_float2(repeating: 0.5),
            sizeNormalized: simd_float2(repeating: 1),
            rotationRadians: 0,
            commandBuffer: targetBuffer
        )

        try model.encode(
            imageBuffer: inputBuffer,
            sequenceInputs: sequenceInputs,
            resetValueBuffer: resetBuffer,
            state: currentState,
            output: output,
            commandBuffer: targetBuffer
        )
        self.currentState = output.state

        guard let readbackSlot = self.readbackSlots.first(where: { $0.acquire() }) else
        {
            // Tracking continues on the GPU even when CPU result consumption
            // falls behind. This deliberately drops a readback, not a frame of
            // recurrent inference and never stalls Fabric's render thread.
            // The synchronous buffer still commits, so the state advances.
            if synchronous { targetBuffer.commit() }
            return
        }

        guard let blitEncoder = targetBuffer.makeBlitCommandEncoder() else
        {
            readbackSlot.release()
            if synchronous { targetBuffer.commit() }
            throw FabricError(.execution(.gpu), severity: .recoverable, message: "Could not create TAPIR result readback encoder")
        }
        let floatStride = MemoryLayout<Float>.stride
        let pointCapacity = configuration.pointCapacity
        blitEncoder.label = "TAPIR result readback"
        blitEncoder.copy(from: output.tracksBuffer, sourceOffset: 0, to: readbackSlot.buffer, destinationOffset: 0, size: pointCapacity * 2 * floatStride)
        blitEncoder.copy(from: output.occlusionLogitsBuffer, sourceOffset: 0, to: readbackSlot.buffer, destinationOffset: pointCapacity * 2 * floatStride, size: pointCapacity * floatStride)
        blitEncoder.copy(from: output.expectedDistanceLogitsBuffer, sourceOffset: 0, to: readbackSlot.buffer, destinationOffset: pointCapacity * 3 * floatStride, size: pointCapacity * floatStride)
        blitEncoder.endEncoding()

        let activePointCount = boundedPoints.count
        let aspect = presentationAspect

        if synchronous
        {
            targetBuffer.commit()
            targetBuffer.waitUntilCompleted()
            defer { readbackSlot.release() }
            if let error = targetBuffer.error
            {
                throw FabricError(.execution(.gpu), severity: .recoverable, message: "TAPIR synchronous inference failed: \(error)")
            }
            let result = Self.decodeResult(
                buffer: readbackSlot.buffer,
                activePointCount: activePointCount,
                pointCapacity: pointCapacity,
                aspect: aspect
            )
            self.outputTrackedPoints.send(result.points)
            self.outputVisible.send(result.visible)
            self.outputVisibilityConfidence.send(result.visibilityConfidence)
            return
        }

        self.completedResultLock.lock()
        let generation = self.sequenceGeneration
        self.completedResultLock.unlock()
        targetBuffer.addCompletedHandler { [weak self, image, model, sequenceInputs, output, readbackSlot] finishedBuffer in
            defer { readbackSlot.release() }
            withExtendedLifetime((image, model, sequenceInputs, output)) {}
            guard finishedBuffer.error == nil, let self else { return }
            let result = Self.decodeResult(
                buffer: readbackSlot.buffer,
                activePointCount: activePointCount,
                pointCapacity: pointCapacity,
                aspect: aspect
            )
            self.completedResultLock.lock()
            if generation == self.sequenceGeneration
            {
                self.completedResult = result
            }
            self.completedResultLock.unlock()
        }
    }

    private func requestedConfiguration(for settings: TAPIRPointTrackingSettings, precision: MPSModelPrecision, computeUnits: MPSModelComputeUnits) -> PreparedConfiguration
    {
        return PreparedConfiguration(
            pointCapacity: Self.pointCapacityOptions.compactMap(Int.init).contains(settings.pointCapacity) ? settings.pointCapacity : 32,
            refinementCount: Self.refinementOptions.compactMap(Int.init).contains(settings.refinementCount) ? settings.refinementCount : 1,
            computePrecision: precision.tapir,
            computeUnits: computeUnits.tapir
        )
    }

    private func apply(modelSettings: TAPIRPointTrackingSettings, modelPrecision: MPSModelPrecision, modelComputeUnits: MPSModelComputeUnits)
    {
        guard modelSettings != self.modelSettings || modelPrecision != self.modelPrecision || modelComputeUnits != self.modelComputeUnits else { return }
        if self.executionEnabled
        {
            do
            {
                try self.prepareModel(self.requestedConfiguration(for: modelSettings, precision: modelPrecision, computeUnits: modelComputeUnits))
            }
            catch
            {
                print("TAPIRPointTrackingNode: could not apply model settings: \(error)")
                return
            }
        }
        self.modelSettings = modelSettings
        self.modelPrecision = modelPrecision
        self.modelComputeUnits = modelComputeUnits
        self.markDirty()
    }

    /// Takes effect on the next frame; the model does not change.
    private func apply(inferenceTiming: MPSInferenceTiming)
    {
        guard inferenceTiming != self.inferenceTiming else { return }
        self.inferenceTiming = inferenceTiming
        self.markDirty()
    }

    private func prepareModel(_ requested: PreparedConfiguration) throws
    {
        guard self.preparedConfiguration != requested || self.model == nil else { return }
        let modelConfiguration = TAPIRConfiguration(
            maximumPointCount: requested.pointCapacity,
            refinementCount: requested.refinementCount,
            computePrecision: requested.computePrecision,
            computeUnits: requested.computeUnits
        )
        let model = try TAPIRSharedModels.model(
            configuration: modelConfiguration,
            commandQueue: self.context.commandQueue
        )
        let preprocessor = try MediaPipeCropPreprocessor(
            device: self.context.device,
            outputWidth: 256,
            outputHeight: 256,
            outputPixelRange: (-1, 1),
            maxFramesInFlight: SharedModelCapacity.framesInFlight
        )
        let readbackLength = requested.pointCapacity * 4 * MemoryLayout<Float>.stride
        let readbackSlots = try (0..<SharedModelCapacity.framesInFlight).map { index -> ReadbackSlot in
            guard let buffer = self.context.device.makeBuffer(length: readbackLength, options: .storageModeShared) else
            {
                throw FabricError(.execution(.outOfMemory), severity: .recoverable, message: "Could not allocate TAPIR readback buffer")
            }
            buffer.label = "TAPIR readback [slot \(index)]"
            return ReadbackSlot(buffer: buffer)
        }

        self.invalidatePreparedModel()
        self.model = model
        self.preprocessor = preprocessor
        self.readbackSlots = readbackSlots
        self.preparedConfiguration = requested
    }

    private func beginSequence(points: ContiguousArray<simd_float2>, image: FabricImage, model: TAPIROnlineModel, pointCapacity: Int) throws
    {
        let aspect = Float(image.presentationSize.height / image.presentationSize.width)
        let rasterPoints = Self.paddedRasterPoints(from: points, aspect: aspect, capacity: pointCapacity)
        self.sequenceInputs = try model.makeSequenceInputs(queryPoints: rasterPoints.map { TAPIRPoint(x: $0.x, y: $0.y) })
        self.currentState = try model.makeCausalState()
        self.modelOutputs = [try model.makeOutput(), try model.makeOutput()]
        self.nextModelOutputIndex = 0
        self.activeQueryPoints = points
        self.completedResultLock.lock()
        self.activePresentationAspect = aspect
        self.sequenceGeneration += 1
        self.completedResult = nil
        self.completedResultLock.unlock()
    }

    private func resetSequence()
    {
        self.sequenceInputs = nil
        self.currentState = nil
        self.modelOutputs = []
        self.nextModelOutputIndex = 0
        self.activeQueryPoints = []
        self.completedResultLock.lock()
        self.activePresentationAspect = nil
        self.sequenceGeneration += 1
        self.completedResult = nil
        self.completedResultLock.unlock()
    }

    private func invalidatePreparedModel()
    {
        self.resetSequence()
        self.preparedConfiguration = nil
        self.preprocessor = nil
        self.model = nil
        self.readbackSlots = []
    }

    private func publishLatestCompletedResult()
    {
        self.completedResultLock.lock()
        let result = self.completedResult
        self.completedResult = nil
        self.completedResultLock.unlock()
        guard let result else { return }
        self.outputTrackedPoints.send(result.points)
        self.outputVisible.send(result.visible)
        self.outputVisibilityConfidence.send(result.visibilityConfidence)
    }

    private func clearPublishedResults()
    {
        self.outputTrackedPoints.send([])
        self.outputVisible.send([])
        self.outputVisibilityConfidence.send([])
    }

    static func paddedRasterPoints(from points: ContiguousArray<simd_float2>, aspect: Float, capacity: Int) -> [simd_float2]
    {
        guard capacity > 0 else { return [] }
        let bounded = points.prefix(capacity).map { self.rasterPoint(from: $0, aspect: aspect) }
        let paddingPoint = bounded.last ?? simd_float2(repeating: Self.modelSize / 2)
        return bounded + Array(repeating: paddingPoint, count: capacity - bounded.count)
    }

    static func rasterPoint(from unitPoint: simd_float2, aspect: Float) -> simd_float2
    {
        let safeAspect = max(aspect, Float.ulpOfOne)
        let normalizedX = (unitPoint.x + 1) / 2
        let normalizedBottomY = (unitPoint.y / safeAspect + 1) / 2
        return simd_float2(
            min(max(normalizedX * Self.modelSize, 0), Self.modelSize - Float.ulpOfOne),
            min(max((1 - normalizedBottomY) * Self.modelSize, 0), Self.modelSize - Float.ulpOfOne)
        )
    }

    static func unitPoint(from rasterPoint: simd_float2, aspect: Float) -> simd_float2
    {
        let normalizedX = rasterPoint.x / Self.modelSize
        let normalizedBottomY = 1 - rasterPoint.y / Self.modelSize
        return simd_float2(normalizedX * 2 - 1, (normalizedBottomY * 2 - 1) * aspect)
    }

    private static func decodeResult(buffer: MTLBuffer, activePointCount: Int, pointCapacity: Int, aspect: Float) -> CompletedResult
    {
        let values = buffer.contents().assumingMemoryBound(to: Float.self)
        var points = ContiguousArray<simd_float2>()
        var visible = ContiguousArray<Bool>()
        var confidence = ContiguousArray<Float>()
        points.reserveCapacity(activePointCount)
        visible.reserveCapacity(activePointCount)
        confidence.reserveCapacity(activePointCount)

        for index in 0..<activePointCount
        {
            points.append(Self.unitPoint(from: simd_float2(values[index * 2], values[index * 2 + 1]), aspect: aspect))
            let occlusionLogit = values[pointCapacity * 2 + index]
            let expectedDistanceLogit = values[pointCapacity * 3 + index]
            let visibilityConfidence = Self.sigmoid(-occlusionLogit) * Self.sigmoid(-expectedDistanceLogit)
            confidence.append(visibilityConfidence)
            visible.append(visibilityConfidence > 0.5)
        }
        return CompletedResult(
            points: points,
            visible: visible,
            visibilityConfidence: confidence
        )
    }

    private static func sigmoid(_ value: Float) -> Float
    {
        1 / (1 + exp(-value))
    }
}
