//
//  MetalFXSpatialUpsample2xNode.swift
//  Fabric
//
//  2x upscales an incoming texture using MetalFX Spatial Upscaling (Metal 3)
//
//  NOTE:
//  - Spatial upscaling is a single-frame effect (no motion/depth needed).
//  - Fabric image processing assumes linear textures internally. See ARCHITECTURE.md.
//
//

import Foundation
import Metal
import MetalFX
import Satin

final class MetalFXSpatialUpsample2xNode: BaseEffectNode
{
    override class var name: String { "Upsample" }
    override class var nodeType: Node.NodeType { .Image(imageType: .Analysis) } // fits Image Processing bucket :contentReference[oaicite:4]{index=4}

    // MetalFX state
    private var spatialScaler: MTLFXSpatialScaler?
    private var cachedInWidth: Int = 0
    private var cachedInHeight: Int = 0
    private var cachedPixelFormat: MTLPixelFormat = .invalid

    // Output texture cache
//    private var outputTexture: MTLTexture?
    
    override func execute(context: GraphExecutionContext,
                          renderPassDescriptor: MTLRenderPassDescriptor,
                          commandBuffer: MTLCommandBuffer)
    {
        guard self.inputTexturePort.valueDidChange || isDirty else {
            return
        }

        guard let inTex = self.inputTexturePort.value?.texture else {
            return
        }

        let inputWidth = inTex.width
        let inputHeight = inTex.height
        let inputFormat  = inTex.pixelFormat

        // Rebuild scaler + output texture if the input description changed
        if self.spatialScaler == nil
            || inputWidth != self.cachedInWidth
            || inputHeight != self.cachedInHeight
            || inputFormat != self.cachedPixelFormat
        {
            self.rebuildScalerAndTargets(for: inTex)
        }

        guard let scaler = self.spatialScaler,
              let outImage = context.graphRenderer?.newImage(withWidth: inTex.width, height: inTex.height)
        else
        {
            self.outputTexturePort.send(nil)
            return
        }

        // Validate usage (best-effort). MetalFX requires the texture usage be a superset of these.
        // (Some upstream nodes may create textures with too-restrictive usage flags.)
        if !inTex.usage.contains(scaler.colorTextureUsage) {
            // Don’t fatalError in a node graph; just drop output.
            // You can swap to a logger node later.
            self.outputTexturePort.send(nil)
            return
        }

        // Per-frame binding & encode (Apple’s recommended pattern) :contentReference[oaicite:5]{index=5}
        scaler.colorTexture = inTex
        scaler.outputTexture = outImage.texture
        
        scaler.encode(commandBuffer: commandBuffer )

        self.outputTexturePort.send(outImage)
    }

    private func rebuildScalerAndTargets(for input: MTLTexture)
    {
         let device = self.context.device

        let inputPixelFormat  = input.pixelFormat
        let inputWidth = input.width
        let inputHeight = input.height
        let outputWidth = inputWidth * 2
        let outputHeight = inputHeight * 2

        let desc = MTLFXSpatialScalerDescriptor()
        desc.inputWidth = inputWidth
        desc.inputHeight = inputHeight
        desc.outputWidth = outputWidth
        desc.outputHeight = outputHeight
        desc.colorTextureFormat = inputPixelFormat
        desc.outputTextureFormat = inputPixelFormat

        // Fabric generally treats images as linear internally :contentReference[oaicite:6]{index=6}.
        // Use .linear so MetalFX interprets input/output appropriately.
        desc.colorProcessingMode = .linear

        guard let scaler = desc.makeSpatialScaler(device: device) else {
            self.spatialScaler = nil
            return
        }

        self.spatialScaler = scaler
        self.cachedInWidth = inputWidth
        self.cachedInHeight = inputHeight
        self.cachedPixelFormat = inputPixelFormat
    }
}
