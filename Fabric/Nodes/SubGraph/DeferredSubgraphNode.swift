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
    
    // Parameters:
    public let inputResolution:Int2Parameter
    public let inputClearColor:Float4Parameter
    
    public override var inputParameters: [any Parameter] {
        [inputResolution,
         inputClearColor]
        + super.inputParameters }

    // Ports:
    public let outputColorTexture:NodePort<EquatableTexture>
    public let outputDepthTexture:NodePort<EquatableTexture>
    
    public override var ports: [any NodePortProtocol] {[outputColorTexture, outputDepthTexture] + super.ports}

    // Ensure we always render!
    public override var isDirty:Bool { get {  self.graph.needsExecution  } set { } }

    
    public required init(context: Context)
    {
        self.inputResolution = Int2Parameter("Resolution", simd_int2(x:1920, y:1080), simd_int2(x:1, y:1), simd_int2(x:8192, y:8192), .inputfield)
        self.inputClearColor = Float4Parameter("Clear Color", simd_float4(repeating:0), .colorpicker)

        self.outputColorTexture = NodePort<EquatableTexture>(name: "Color Texture", kind: .Outlet)
        self.outputDepthTexture = NodePort<EquatableTexture>(name: "Depth Texture", kind: .Outlet)

        
        super.init(context: context)
        
        self.graphRenderer.renderer.depthStoreAction = .store
        self.graphRenderer.renderer.depthLoadAction = .clear
        self.graphRenderer.renderer.size.width = 1920
        self.graphRenderer.renderer.size.height = 1080

    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputClearColorParam
        case inputResolution
        case outputColorTexturePort
        case outputDepthTexturePort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputClearColor, forKey: .inputClearColorParam)
        try container.encode(self.inputResolution, forKey: .inputResolution)

        try container.encode(self.outputColorTexture, forKey: .outputColorTexturePort)
        try container.encode(self.outputDepthTexture, forKey: .outputDepthTexturePort)
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.outputColorTexture = try container.decode(NodePort<EquatableTexture>.self , forKey:.outputColorTexturePort)
        self.outputDepthTexture =  try container.decode(NodePort<EquatableTexture>.self , forKey:.outputDepthTexturePort)

        self.inputClearColor = try container.decode(Float4Parameter.self , forKey:.inputClearColorParam)
        self.inputResolution = try container.decode(Int2Parameter.self, forKey: .inputResolution)

        try super.init(from: decoder)
        
        self.graphRenderer.renderer.depthStoreAction = .store
        self.graphRenderer.renderer.depthLoadAction = .clear
        self.graphRenderer.renderer.size.width = 1920
        self.graphRenderer.renderer.size.height = 1080

    }
    
    override public func startExecution(context:GraphExecutionContext)
    {
        self.graphRenderer.startExecution(graph: self.graph)
    }
    
    override public func stopExecution(context:GraphExecutionContext)
    {
        self.graphRenderer.stopExecution(graph: self.graph)
    }

    override public func enableExecution(context:GraphExecutionContext)
    {
        self.graphRenderer.enableExecution(graph: self.graph)
    }
    
    override public func disableExecution(context:GraphExecutionContext)
    {
        self.graphRenderer.disableExecution(graph: self.graph)
    }
    
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: any MTLCommandBuffer)
    {
        
        let rpd1 = MTLRenderPassDescriptor()
    
        if (self.graphRenderer.renderer.size.width != Float(self.inputResolution.value.x))
            || (self.graphRenderer.renderer.size.height != Float(self.inputResolution.value.y))
        {
            self.graphRenderer.renderer.resize( (width:Float(self.inputResolution.value.x), height:Float(self.inputResolution.value.y) ) )
        }
       
        if self.inputClearColor.valueDidChange
        {
            self.graphRenderer.renderer.clearColor = .init( self.inputClearColor.value )
        }
                    
        self.graphRenderer.execute(graph: self.graph,
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
    
}
