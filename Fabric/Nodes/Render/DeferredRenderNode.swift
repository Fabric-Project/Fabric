//
//  DeferredRender.swift
//  Fabric
//
//  Created by Anton Marini on 5/6/25.
//

import Foundation
import Satin
import simd
import Metal

class DeferredRenderNode : Node, NodeProtocol
{
    static let name = "Deferred Render"
    static var nodeType = Node.NodeType.Renderer
    
    // Parameters
    let inputResolution = Int2Parameter("Resolution", simd_int2(x:1920, y:1080), simd_int2(x:1, y:1), simd_int2(x:8192, y:8192), .inputfield)
    let inputClearColor = Float4Parameter("Clear Color", simd_float4(repeating:0), .colorpicker)
    
    override var inputParameters: [any Parameter] { super.inputParameters + [inputResolution, inputClearColor] }
    
    // Ensure we always render!
    override var isDirty:Bool { get {  true  } set { } }
    
    // Ports
    let inputCamera = NodePort<Camera>(name: "Camera", kind: .Inlet)
    let inputScene = NodePort<Object>(name: "Scene", kind: .Inlet)
    
    let outputColorTexture = NodePort<EquatableTexture>(name: "Color Texture", kind: .Outlet)
    let outputDepthTexture = NodePort<EquatableTexture>(name: "Depth Texture", kind: .Outlet)

    private let renderer:Renderer
    
    override var ports: [any AnyPort] { super.ports +  [inputCamera, inputScene, outputColorTexture, outputDepthTexture] }
    
    required init(context:Context)
    {
        self.renderer = Renderer(context: context, frameBufferOnly:false)
        self.renderer.depthStoreAction = .store
        self.renderer.depthLoadAction = .clear
        self.renderer.size.width = 1920
        self.renderer.size.height = 1080

        super.init(context: context)
    }
    
    required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.renderer = Renderer(context: decodeContext.documentContext, frameBufferOnly:false)
        self.renderer.depthStoreAction = .store
        self.renderer.depthLoadAction = .clear
        self.renderer.size.width = 1920
        self.renderer.size.height = 1080

        
        try super.init(from: decoder)
    }

    override func evaluate(atTime:TimeInterval,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if let object = self.inputScene.value,
           let camera = self.inputCamera.value
        {
            let rpd1 = MTLRenderPassDescriptor()

            self.renderer.clearColor = .init( self.inputClearColor.value )
                        
            renderer.draw(renderPassDescriptor: rpd1,
                          commandBuffer: commandBuffer,
                          scene: object,
                          camera: camera)
            
            if let texture = renderer.colorTexture
            {
                self.outputColorTexture.send( EquatableTexture(texture: texture) )
            }
//            else
//            {
//                self.outputColorTexture.send( nil )
//
//            }
            
            if let texture = renderer.depthTexture
            {
                self.outputDepthTexture.send( EquatableTexture(texture: texture) )
            }
//            else
//            {
//                self.outputDepthTexture.send( nil )
//            }
        }
    }
    
    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        //        renderer.resize(size)
    }
}
