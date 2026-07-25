//
//  SubgraphNode.swift
//  Fabric
//
//  Created by Anton Marini on 6/22/25.
//

import Foundation
import Satin
import simd
import Metal
import SwiftUI

private struct DeferredSubgraphNodeSettingsView: View
{
    @Bindable var model: DeferredSubgraphNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Toggle("Enable Deferred MRT Outputs", isOn: $model.deferredMRTEnabled)
            Text("Adds auxiliary outputs for albedo, normals, PBR, velocity, and emissive textures using Satin's deferred geometry pipeline.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

public class DeferredSubgraphNode: SubgraphNode
{
    private struct AuxiliaryOutputPortDescriptor
    {
        let registryName: String
        let displayName: String
        let description: String
    }

    private enum CodingKeys: String, CodingKey
    {
        case deferredMRTEnabled
    }

    @Observable final class SettingsModel {
        var deferredMRTEnabled: Bool {
            didSet {
                guard deferredMRTEnabled != node?.deferredMRTEnabled else { return }
                node?.deferredMRTEnabled = deferredMRTEnabled
            }
        }
        private weak var node: DeferredSubgraphNode?
        init(node: DeferredSubgraphNode) {
            self.node = node
            self.deferredMRTEnabled = node.deferredMRTEnabled
        }
    }

    private lazy var _settingsModel = SettingsModel(node: self)

    private static let deferredOutputs: RendererOutputs = [.color, .albedo, .normals, .pbr, .velocity, .emissive]
    private static let auxiliaryOutputPorts: [AuxiliaryOutputPortDescriptor] = [
        .init(registryName: "outputAlbedoTexture", displayName: "Albedo Texture", description: "Deferred albedo render target from the subgraph"),
        .init(registryName: "outputNormalsTexture", displayName: "Normals Texture", description: "Deferred normal render target from the subgraph"),
        .init(registryName: "outputPBRTexture", displayName: "PBR Texture", description: "Deferred PBR render target from the subgraph"),
        .init(registryName: "outputVelocityTexture", displayName: "Velocity Texture", description: "Deferred velocity render target from the subgraph"),
        .init(registryName: "outputEmissiveTexture", displayName: "Emissive Texture", description: "Deferred emissive render target from the subgraph"),
    ]

    public override class var name:String { "Render To Image and Depth" }
    public override class var nodeType: Node.NodeType { .Subgraph }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Renders a Sub Graph to an Color Image and Depth Image, suitable for post processing."}

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 1920, .inputfield, "Output texture width in pixels"))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 1080, .inputfield, "Output texture height in pixels"))),
            ("inputClearColor", ParameterPort(parameter: Float4Parameter("Clear Color", simd_float4(repeating:0), .colorpicker, "Background color for the render target"))),
            ("outputColorTexture", NodePort<FabricImage>(name: "Color Texture", kind: .Outlet, description: "Rendered color output from the subgraph")),
            ("outputDepthTexture", NodePort<FabricImage>(name: "Depth Texture", kind: .Outlet, description: "Rendered depth buffer from the subgraph")),
        ] + ports
    }
    
    // Proxy Port
    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputClearColor: ParameterPort<simd_float4> { port(named: "inputClearColor") }
    public var outputColorTexture: NodePort<FabricImage> { port(named: "outputColorTexture") }
    public var outputDepthTexture: NodePort<FabricImage> { port(named: "outputDepthTexture") }
    
    override public var object:Object? {
        return nil
    }
    
    private var rendererNeedsSetup = true
    var graphRenderer:GraphRenderer

    public var deferredMRTEnabled: Bool = false
    {
        didSet
        {
            guard oldValue != deferredMRTEnabled else { return }
            self.synchronizeDeferredConfiguration()
        }
    }

    public required init(context: Context)
    {
        self.graphRenderer = GraphRenderer(context: context)
        
        super.init(context: context)
        self.synchronizeDeferredConfiguration()
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        self.graphRenderer = GraphRenderer(context: decodeContext.documentContext)

        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deferredMRTEnabled = try container.decodeIfPresent(Bool.self, forKey: .deferredMRTEnabled) ?? false
        self.synchronizeDeferredConfiguration()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.deferredMRTEnabled, forKey: .deferredMRTEnabled)
    }
    
    private func setupRenderer()
    {
        self.graphRenderer.renderEncoder.label = "Deferred Subgraph"
        self.graphRenderer.renderEncoder.colorStoreAction = .store
        self.graphRenderer.renderEncoder.depthStoreAction = .store
        self.graphRenderer.renderEncoder.depthLoadAction = .clear
        self.graphRenderer.renderEncoder.size.width = Float(self.inputWidth.value ?? 1920)
        self.graphRenderer.renderEncoder.size.height = Float(self.inputHeight.value ?? 1080 )
        
        self.graphRenderer.renderEncoder.colorTextureStorageMode = .private
        self.graphRenderer.renderEncoder.colorMultisampleTextureStorageMode = .private
        
        self.graphRenderer.renderEncoder.depthTextureStorageMode = .private
        self.graphRenderer.renderEncoder.depthMultisampleTextureStorageMode = .private
        
        self.graphRenderer.renderEncoder.stencilTextureStorageMode = .private
        self.graphRenderer.renderEncoder.stencilMultisampleTextureStorageMode = .private

        self.graphRenderer.renderEncoder.albedoTextureStorageMode = .private
        self.graphRenderer.renderEncoder.normalTextureStorageMode = .private
        self.graphRenderer.renderEncoder.pbrTextureStorageMode = .private
        self.graphRenderer.renderEncoder.velocityTextureStorageMode = .private
        self.graphRenderer.renderEncoder.emissiveTextureStorageMode = .private
        
        self.graphRenderer.resize(size: (Float(self.inputWidth.value ?? 1920), Float(self.inputHeight.value ?? 1080 )), scaleFactor: 1.0)
        self.graphRenderer.renderEncoder.clearColor = .init(self.inputClearColor.value ?? simd_float4(repeating: 0))
        self.rendererNeedsSetup = false
    }

    private func synchronizeDeferredConfiguration()
    {
        self.syncAuxiliaryOutputPorts()
        self.rebuildGraphRenderer()
        self.markDirty()
    }

    private func syncAuxiliaryOutputPorts()
    {
        for descriptor in Self.auxiliaryOutputPorts
        {
            if deferredMRTEnabled
            {
                guard self.findPort(named: descriptor.registryName, as: Port.self) == nil else { continue }

                let port = NodePort<FabricImage>(
                    name: descriptor.displayName,
                    kind: .Outlet,
                    description: descriptor.description
                )
                self.addDynamicPort(port, name: descriptor.registryName)
            }
            else if let port = self.findPort(named: descriptor.registryName, as: Port.self)
            {
                self.removePort(port)
            }
        }
    }

    private func rebuildGraphRenderer()
    {
        self.graphRenderer = GraphRenderer(context: self.makeRendererContext())
        self.rendererNeedsSetup = true
    }

    private func makeRendererContext() -> Context
    {
        guard self.deferredMRTEnabled else {
            return self.context
        }

        return Context(
            id:self.context.id,
            device: self.context.device,
            sampleCount: self.context.sampleCount,
            colorPixelFormat: self.context.colorPixelFormat,
            depthPixelFormat: self.context.depthPixelFormat,
            stencilPixelFormat: self.context.stencilPixelFormat,
            vertexAmplificationCount: self.context.vertexAmplificationCount,
            maxBuffersInFlight: self.context.maxBuffersInFlight,
            renderingMode: .deferredGeometry,
            activeOutputs: Self.deferredOutputs,
            albedoPixelFormat: self.context.albedoPixelFormat,
            normalsPixelFormat: self.context.normalsPixelFormat,
            pbrPixelFormat: self.context.pbrPixelFormat,
            velocityPixelFormat: self.context.velocityPixelFormat,
            emissivePixelFormat: self.context.emissivePixelFormat
        )
    }

    private func sendAuxiliaryTexture(_ texture: MTLTexture?, toPortNamed portName: String)
    {
        guard let port = self.findPort(named: portName, as: NodePort<FabricImage>.self) else { return }

        if let texture
        {
            port.send(FabricImage.unmanaged(texture: texture))
        }
        else
        {
            port.send(nil)
        }
    }
    
    override public func startExecution(renderer:GraphRenderer) throws
    {
        if self.rendererNeedsSetup
        {
            self.setupRenderer()
        }

        try self.graphRenderer.startExecution(graph: self.subGraph)
    }
    
    override public func stopExecution(renderer:GraphRenderer) throws
    {
        try self.graphRenderer.stopExecution(graph: self.subGraph)
    }

    override public func enableExecution(renderer:GraphRenderer) throws
    {
        try self.graphRenderer.enableExecution(graph: self.subGraph)
    }
    
    override public func disableExecution(renderer:GraphRenderer) throws
    {
        try self.graphRenderer.disableExecution(graph: self.subGraph)
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        if self.rendererNeedsSetup
        {
            self.setupRenderer()
        }

        let rpd1 = MTLRenderPassDescriptor()
    
        if self.inputWidth.valueDidChange || self.inputHeight.valueDidChange,
           let width = self.inputWidth.value,
           let height = self.inputHeight.value
        {
            if (self.graphRenderer.renderEncoder.size.width != Float(width))
                || (self.graphRenderer.renderEncoder.size.height != Float(height))
            {
                self.graphRenderer.resize(size: (Float(width), Float(height)), scaleFactor: 1.0)
            }
        }
       
        if self.inputClearColor.valueDidChange,
           let clearColor = self.inputClearColor.value
        {
            self.graphRenderer.renderEncoder.clearColor = .init( clearColor )
        }
                    
        guard let width = self.inputWidth.value,
              let height = self.inputHeight.value
        else { return }

            
        let outputImage = try self.graphRenderer.newImage(withWidth: width, height: height)
        rpd1.colorAttachments[0].texture = outputImage.texture

        try self.graphRenderer.executeAndDraw(graph: self.subGraph,
                                              executionInfo: executionInfo,
                                              renderPassDescriptor: rpd1,
                                              commandBuffer: commandBuffer)

        self.outputColorTexture.send(outputImage)
        
        if let texture = self.graphRenderer.renderEncoder.depthTexture
        {
            self.outputDepthTexture.send( FabricImage.unmanaged(texture: texture) )
        }
        else
        {
            self.outputDepthTexture.send( nil )
        }

        if self.deferredMRTEnabled
        {
            self.sendAuxiliaryTexture(self.graphRenderer.renderEncoder.albedoTexture, toPortNamed: "outputAlbedoTexture")
            self.sendAuxiliaryTexture(self.graphRenderer.renderEncoder.normalTexture, toPortNamed: "outputNormalsTexture")
            self.sendAuxiliaryTexture(self.graphRenderer.renderEncoder.pbrTexture, toPortNamed: "outputPBRTexture")
            self.sendAuxiliaryTexture(self.graphRenderer.renderEncoder.velocityTexture, toPortNamed: "outputVelocityTexture")
            self.sendAuxiliaryTexture(self.graphRenderer.renderEncoder.emissiveTexture, toPortNamed: "outputEmissiveTexture")
        }
        
        // We need to call this to ensure any published port values also get forwarded.
        self.forwardPortValues(force:true)
    }
    
    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
    }

    override public func providesSettingsView() -> Bool
    {
        true
    }

    override public func settingsView() -> AnyView
    {
        AnyView(DeferredSubgraphNodeSettingsView(model: _settingsModel))
    }

    override public var settingsSize: SettingsViewSize
    {
        .Small
    }
    
}
