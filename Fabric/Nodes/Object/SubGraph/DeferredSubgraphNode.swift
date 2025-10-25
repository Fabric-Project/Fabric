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

public class DeferredSubgraphNode: SubgraphNode
{
    public override class var name:String { "Render To Image and Depth" }
    public override class var nodeType: Node.NodeType { .Subgraph }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .TimeBase }
    override public class var nodeDescription: String { "Renders a Sub Graph to an Color Image and Depth Image, suitable for post processing."}

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 1920, .inputfield))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 1080, .inputfield))),
            ("inputClearColor", ParameterPort(parameter: Float4Parameter("Clear Color", simd_float4(repeating:0), .colorpicker))),
            ("outputColorTexture", NodePort<EquatableTexture>(name: "Color Texture", kind: .Outlet)),
            ("outputDepthTexture", NodePort<EquatableTexture>(name: "Depth Texture", kind: .Outlet)),
        ] + ports
    }
    
    // Proxy Port
    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputClearColor: ParameterPort<simd_float4> { port(named: "inputClearColor") }
    public var outputColorTexture: NodePort<EquatableTexture> { port(named: "outputColorTexture") }
    public var outputDepthTexture: NodePort<EquatableTexture> { port(named: "outputDepthTexture") }
    
    override public var object:Object? {
        return nil
    }
    
    let graphRenderer:GraphRenderer

    public required init(context: Context)
    {
        self.graphRenderer = GraphRenderer(context: context)
        
        super.init(context: context)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        self.graphRenderer = GraphRenderer(context: decodeContext.documentContext)

        try super.init(from: decoder)
    }
    
    private func setupRenderer()
    {
        self.graphRenderer.renderer.label = "Deferred Subgraph"
        self.graphRenderer.renderer.colorStoreAction = .store
        self.graphRenderer.renderer.depthStoreAction = .store
        self.graphRenderer.renderer.depthLoadAction = .clear
        self.graphRenderer.renderer.size.width = Float(self.inputWidth.value ?? 1920)
        self.graphRenderer.renderer.size.height = Float(self.inputHeight.value ?? 1080 )
        
        self.graphRenderer.renderer.colorTextureStorageMode = .private
        self.graphRenderer.renderer.colorMultisampleTextureStorageMode = .private
        
        self.graphRenderer.renderer.depthTextureStorageMode = .private
        self.graphRenderer.renderer.depthMultisampleTextureStorageMode = .private
        
        self.graphRenderer.renderer.stencilTextureStorageMode = .private
        self.graphRenderer.renderer.stencilMultisampleTextureStorageMode = .private
    }
    
    override public func startExecution(context:GraphExecutionContext)
    {
        self.setupRenderer()

        self.graphRenderer.startExecution(graph: self.subGraph, executionContext: context)
    }
    
    override public func stopExecution(context:GraphExecutionContext)
    {
        self.graphRenderer.stopExecution(graph: self.subGraph, executionContext: context)
    }

    override public func enableExecution(context:GraphExecutionContext)
    {
        self.graphRenderer.enableExecution(graph: self.subGraph, executionContext: context)
    }
    
    override public func disableExecution(context:GraphExecutionContext)
    {
        self.graphRenderer.disableExecution(graph: self.subGraph, executionContext: context)
    }
    
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {
        let rpd1 = MTLRenderPassDescriptor()
    
        if self.inputWidth.valueDidChange || self.inputHeight.valueDidChange,
           let width = self.inputWidth.value,
           let height = self.inputHeight.value
        {
            if (self.graphRenderer.renderer.size.width != Float(width))
                || (self.graphRenderer.renderer.size.height != Float(height))
            {
                self.graphRenderer.renderer.resize( (width:Float(width), height:Float(height) ) )
            }
        }
       
        if self.inputClearColor.valueDidChange,
           let clearColor = self.inputClearColor.value
        {
            self.graphRenderer.renderer.clearColor = .init( clearColor )
        }
                    
        rpd1.colorAttachments[0].texture = self.graphRenderer.renderer.colorTexture

        self.graphRenderer.executeAndDraw(graph: self.subGraph,
                                   executionContext: context,
                                   renderPassDescriptor: rpd1,
                                   commandBuffer: commandBuffer)
        
        if let texture = self.graphRenderer.renderer.colorTexture
        {
            self.outputColorTexture.send( EquatableTexture(texture: texture) )
        }
        else
        {
            self.outputColorTexture.send( nil )
        }
        
        if let texture = self.graphRenderer.renderer.depthTexture
        {
            self.outputDepthTexture.send( EquatableTexture(texture: texture) )
        }
        else
        {
            self.outputDepthTexture.send( nil )
        }
    }
    
    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.graphRenderer.resize(size: size, scaleFactor: scaleFactor)
    }
    
}
