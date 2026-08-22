//
//  LucasKanadeOpticalFlowNode.swift
//  Fabric
//
//  GPU-native pyramidal Lucas-Kanade optical flow.
//  Reference: CShade cFlow.fx (github.com/papadanku/CShade)
//
//  Output: RG16Float FabricImage. R = horizontal UV-space displacement,
//  G = vertical UV-space displacement, both in [-1, 1].
//
//  This node is stateless: it computes flow between the two input images each
//  frame without managing any frame history internally. Temporal blending and
//  feedback loops are the caller's responsibility — use Fabric's delay/feedback
//  nodes to supply the previous frame via inputPrevImage.
//
//  Pyramid: preprocessing writes mip zero and a Metal blit encoder generates
//  the filtered mip chain used by the coarse-to-fine solver.
//

import Foundation
import Satin
import Metal

public class LucasKanadeOpticalFlowNode: Node
{
    override public class var name: String { "Lucas-Kanade Optical Flow" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Dense GPU optical flow via pyramidal Lucas-Kanade. Outputs RG16Float (R=dX, G=dY) in UV space [-1,1]. Connect inputPrevImage to a delayed/feedback copy of the input for motion estimation."
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        return ports + [
            ("inputImage",
             NodePort<FabricImage>(name: "Image", kind: .Inlet,
                                  description: "Current frame")),
            ("inputPrevImage",
             NodePort<FabricImage>(name: "Prev Image", kind: .Inlet,
                                  description: "Previous frame — connect a delayed/feedback copy of inputImage. If unconnected, falls back to inputImage (outputs zero flow).")),
            ("inputQuality",
             ParameterPort(parameter: StringParameter(
                "Quality", "Medium",
                ["Low", "Medium", "High", "Very High"], .dropdown,
                "Pyramid depth: Low = 2 LK levels, Medium = 3, High = 4, Very High = 5"))),
            ("inputPreviousFlow",
             NodePort<FabricImage>(name: "Previous Flow", kind: .Inlet,
                                  description: "Optional previous RG flow field used for temporal smoothing")),
            ("inputTemporalSmoothing",
             ParameterPort(parameter: FloatParameter(
                "Temporal Smoothing", 0.0, 0.0, 0.99, .slider,
                "Previous-flow weight. Zero disables smoothing; 0.9 retains 90% of the previous flow."))),
            ("outputFlow",
             NodePort<FabricImage>(name: "Flow", kind: .Outlet,
                                  description: "RG16Float: R = dX, G = dY in UV space [-1, 1]")),
        ]
    }

    public var inputImage:     NodePort<FabricImage> { port(named: "inputImage") }
    public var inputPrevImage: NodePort<FabricImage> { port(named: "inputPrevImage") }
    public var inputQuality:   NodePort<String>       { port(named: "inputQuality") }
    public var inputPreviousFlow: NodePort<FabricImage> { port(named: "inputPreviousFlow") }
    public var inputTemporalSmoothing: NodePort<Float> { port(named: "inputTemporalSmoothing") }
    public var outputFlow:     NodePort<FabricImage>  { port(named: "outputFlow") }

    // ── Compute pipelines ─────────────────────────────────────────────────
    private var preprocessPipeline:        MTLComputePipelineState?
    private var flowLevelPipeline:         MTLComputePipelineState?
    private var medianFilterPipeline:       MTLComputePipelineState?
    private var bilateralUpsamplePipeline: MTLComputePipelineState?
    private var temporalSmoothingPipeline:  MTLComputePipelineState?

    // Uniform struct — mirrors LKUniforms in LucasKanadeFlow.metal exactly.
    private struct LKUniforms {
        var resolution:  SIMD2<UInt32>
        var pyramidLevel: UInt32
        var useInitFlow: UInt32
    }

    // MARK: - Init

    public required init(context: Context) {
        super.init(context: context)
        setupComputePipelines()
    }

    public required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
        setupComputePipelines()
    }

    // MARK: - Pipeline setup

    private func setupComputePipelines() {
        let device = self.context.device
        let compiler = MetalFileCompiler(watch: false)

        guard
            let shaderURL = Bundle.module.url(forResource: "LucasKanadeFlow",
                                              withExtension: "metal",
                                              subdirectory: "Compute/OpticalFlow"),
            let source    = try? compiler.parse(shaderURL),
            let library   = try? device.makeLibrary(source: source, options: nil)
        else { return }

        func pipeline(_ name: String) -> MTLComputePipelineState? {
            guard let fn = library.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }

        preprocessPipeline        = pipeline("lk_preprocess")
        flowLevelPipeline         = pipeline("lk_flow_level")
        medianFilterPipeline       = pipeline("lk_median_filter")
        bilateralUpsamplePipeline = pipeline("lk_bilateral_upsample")
        temporalSmoothingPipeline  = pipeline("lk_temporal_smooth")
    }

    // MARK: - Execute

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard
            self.inputImage.valueDidChange
                || self.inputPrevImage.valueDidChange
                || self.inputQuality.valueDidChange
                || self.inputPreviousFlow.valueDidChange
                || self.inputTemporalSmoothing.valueDidChange
        else { return }

        guard let inTex = self.inputImage.value?.texture else
        {
            outputFlow.send(nil)
            return
        }

        guard
            let preProc = preprocessPipeline,
            let flowLvl = flowLevelPipeline,
            let median = medianFilterPipeline,
            let bilat = bilateralUpsamplePipeline,
            let temporalSmooth = temporalSmoothingPipeline
        else {
            throw FabricError(.execution(.gpu),
                              severity: .recoverable,
                              message: "Lucas-Kanade Optical Flow compute pipelines are unavailable")
        }

        // Fall back to the current frame as "previous" when inputPrevImage is not
        // connected — produces zero flow, which is the correct identity output.
        let prevInTex = self.inputPrevImage.value?.texture ?? inTex

        let W       = inTex.width
        let H       = inTex.height
        let quality = self.inputQuality.value ?? "Medium"
        let cfg     = levelConfig(for: quality)

        commandBuffer.pushDebugGroup("Lucas-Kanade Optical Flow (\(W)×\(H) \(quality))")
        defer { commandBuffer.popDebugGroup() }

        let currentPyramid = try renderer.newImage(withWidth: W,
                                                   height: H,
                                                   format: .rgba16Float,
                                                   mipmapped: true)
        let previousPyramid = try renderer.newImage(withWidth: W,
                                                    height: H,
                                                    format: .rgba16Float,
                                                    mipmapped: true)
        currentPyramid.texture.label = "LK Current Feature Pyramid"
        previousPyramid.texture.label = "LK Previous Feature Pyramid"

        // ── LK flow textures (coarsest → finest) ─────────────────────────
        var flowImages: [FabricImage] = []
        for lvl in 0 ..< cfg.levelCount {
            let shift = cfg.coarsestShift - lvl
            let lw    = max(1, W >> shift)
            let lh    = max(1, H >> shift)
            let img = try renderer.newImage(withWidth: lw, height: lh, format: .rg16Float)
            img.texture.label = "LK Flow Level \(lvl) (\(lw)×\(lh))"
            flowImages.append(img)
        }

        // Bilateral upsample chain toward full resolution
        var upsampledFlowImages: [FabricImage] = []
        var bW = flowImages.last!.texture.width
        var bH = flowImages.last!.texture.height
        for _ in 0 ..< cfg.bilatPassCount {
            bW = min(W, bW * 2)
            bH = min(H, bH * 2)
            let img = try renderer.newImage(withWidth: bW, height: bH, format: .rg16Float)
            img.texture.label = "LK Edge-Aware Upsample \(upsampledFlowImages.count) (\(bW)×\(bH))"
            upsampledFlowImages.append(img)
        }

        let unusedCoarseFlow = try renderer.newImage(
            withWidth: flowImages[0].texture.width,
            height: flowImages[0].texture.height,
            format: .rg16Float
        )
        let medianFlow = try renderer.newImage(
            withWidth: flowImages.last!.texture.width,
            height: flowImages.last!.texture.height,
            format: .rg16Float
        )

        // Preprocessing must finish before the blit encoder generates mips.
        guard let enc = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu),
                              severity: .recoverable,
                              message: "Could not create Lucas-Kanade preprocess compute encoder")
        }
        enc.label = "LK Preprocess"
        enc.pushDebugGroup("LK Preprocess")
        enc.setComputePipelineState(preProc)
        enc.setTexture(inTex,                   index: 0)
        enc.setTexture(currentPyramid.texture,  index: 1)
        dispatch(enc, width: W, height: H)
        enc.setTexture(prevInTex,               index: 0)
        enc.setTexture(previousPyramid.texture, index: 1)
        dispatch(enc, width: W, height: H)
        enc.popDebugGroup()
        enc.endEncoding()

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else
        {
            throw FabricError(.execution(.gpu),
                              severity: .recoverable,
                              message: "Could not create Lucas-Kanade mipmap blit encoder")
        }
        blitEncoder.label = "LK Generate Feature Mipmaps"
        blitEncoder.generateMipmaps(for: currentPyramid.texture)
        blitEncoder.generateMipmaps(for: previousPyramid.texture)
        blitEncoder.endEncoding()

        guard let flowEncoder = commandBuffer.makeComputeCommandEncoder() else
        {
            throw FabricError(.execution(.gpu),
                              severity: .recoverable,
                              message: "Could not create Lucas-Kanade flow compute encoder")
        }
        // Image allocation below can throw; the encoder has to close on that
        // path too, or the next node on this command buffer cannot make one.
        defer { flowEncoder.endEncoding() }

        flowEncoder.label = "LK Flow"
        let barrier: () -> Void = { flowEncoder.memoryBarrier(scope: .textures) }

        // ── LK pyramid levels (coarsest → finest) ────────────────────────
        for (i, flowImage) in flowImages.enumerated() {
            let shift = cfg.coarsestShift - i
            let lw    = flowImage.texture.width
            let lh    = flowImage.texture.height
            var u = LKUniforms(
                resolution:  SIMD2<UInt32>(UInt32(lw), UInt32(lh)),
                pyramidLevel: UInt32(shift),
                useInitFlow: (i == 0) ? 0 : 1
            )
            flowEncoder.pushDebugGroup("LK Level \(i): \(lw)×\(lh) (shift=\(shift))")
            flowEncoder.setComputePipelineState(flowLvl)
            flowEncoder.setTexture(previousPyramid.texture, index: 0)
            flowEncoder.setTexture(currentPyramid.texture, index: 1)
            flowEncoder.setTexture(i == 0 ? unusedCoarseFlow.texture : flowImages[i - 1].texture,
                                   index: 2)
            flowEncoder.setTexture(flowImage.texture, index: 3)
            flowEncoder.setBytes(&u, length: MemoryLayout<LKUniforms>.size, index: 0)
            dispatchGroups(flowEncoder, width: lw, height: lh)
            flowEncoder.popDebugGroup()
            barrier()
        }

        flowEncoder.pushDebugGroup("LK Median Outlier Rejection")
        flowEncoder.setComputePipelineState(median)
        flowEncoder.setTexture(flowImages.last!.texture, index: 0)
        flowEncoder.setTexture(medianFlow.texture, index: 1)
        dispatch(flowEncoder,
                 width: medianFlow.texture.width,
                 height: medianFlow.texture.height)
        flowEncoder.popDebugGroup()

        let temporalSmoothing = min(max(inputTemporalSmoothing.value ?? 0.0, 0.0), 0.99)
        let previousFlowTexture = inputPreviousFlow.value?.texture
        let shouldApplyTemporalSmoothing = previousFlowTexture != nil && temporalSmoothing > 0.0
        if upsampledFlowImages.isEmpty == false || shouldApplyTemporalSmoothing {
            barrier()
        }

        // ── Edge-aware upsample chain ─────────────────────────────────────
        var prevFlowTex = medianFlow.texture
        for (idx, upsampledFlowImage) in upsampledFlowImages.enumerated() {
            let bwOut = upsampledFlowImage.texture.width
            let bhOut = upsampledFlowImage.texture.height
            flowEncoder.pushDebugGroup("LK Edge-Aware Upsample \(idx) (\(bwOut)×\(bhOut))")
            flowEncoder.setComputePipelineState(bilat)
            flowEncoder.setTexture(prevFlowTex, index: 0)
            flowEncoder.setTexture(currentPyramid.texture,
                                   index: 1)
            flowEncoder.setTexture(upsampledFlowImage.texture, index: 2)
            dispatchEdgeAwareUpsample(flowEncoder, width: bwOut, height: bhOut)
            flowEncoder.popDebugGroup()
            if idx < upsampledFlowImages.count - 1 || shouldApplyTemporalSmoothing {
                barrier()
            }
            prevFlowTex = upsampledFlowImage.texture
        }

        let reconstructedFlow = upsampledFlowImages.last ?? medianFlow
        var outputImage = reconstructedFlow

        if let previousFlowTexture,
           shouldApplyTemporalSmoothing
        {
            let temporallySmoothedFlow = try renderer.newImage(withWidth: W,
                                                               height: H,
                                                               format: .rg16Float)

            var previousFlowWeight = temporalSmoothing
            flowEncoder.pushDebugGroup("LK Temporal Smoothing")
            flowEncoder.setComputePipelineState(temporalSmooth)
            flowEncoder.setTexture(reconstructedFlow.texture, index: 0)
            flowEncoder.setTexture(previousFlowTexture, index: 1)
            flowEncoder.setTexture(temporallySmoothedFlow.texture, index: 2)
            flowEncoder.setBytes(&previousFlowWeight,
                                 length: MemoryLayout<Float>.size,
                                 index: 0)
            dispatch(flowEncoder, width: W, height: H)
            flowEncoder.popDebugGroup()
            outputImage = temporallySmoothedFlow
        }

        outputFlow.send(outputImage)
    }

    // MARK: - Helpers

    private struct LKConfig {
        let levelCount:    Int
        let coarsestShift: Int   // coarsest LK level width = W >> coarsestShift
        let bilatPassCount: Int
    }

    private func levelConfig(for quality: String) -> LKConfig {
        switch quality {
        case "Low":       return LKConfig(levelCount: 2, coarsestShift: 4, bilatPassCount: 3)
        case "High":      return LKConfig(levelCount: 4, coarsestShift: 4, bilatPassCount: 1)
        case "Very High": return LKConfig(levelCount: 5, coarsestShift: 4, bilatPassCount: 0)
        default:          return LKConfig(levelCount: 3, coarsestShift: 4, bilatPassCount: 2)
        }
    }

    // dispatchThreadgroups for lk_flow_level: edge threadgroups get full 256-thread
    // populations so the cooperative shPrev load is complete before the barrier.
    private func dispatchGroups(_ enc: MTLComputeCommandEncoder, width: Int, height: Int) {
        enc.dispatchThreadgroups(
            MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    }

    // dispatchThreads for kernels without shared memory.
    private func dispatch(_ enc: MTLComputeCommandEncoder, width: Int, height: Int) {
        enc.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    }

    // The edge-aware kernel keeps eighteen samples and eight candidate sums
    // live per thread. Smaller groups leave more room for concurrent SIMD
    // groups when register pressure limits occupancy.
    private func dispatchEdgeAwareUpsample(_ encoder: MTLComputeCommandEncoder,
                                           width: Int,
                                           height: Int)
    {
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
    }
}
