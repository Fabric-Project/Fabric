//
//  Render.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

class RenderNode : Node, NodeProtocol
{
    static let name = "Scene Render"
    static var nodeType = Node.NodeType.Renderer

    // Parameters
    let inputClearColor = GenericParameter<simd_float4>("Clear Color", simd_float4(repeating:0), .colorpicker)

    override var inputParameters: [any Parameter] { super.inputParameters + [inputClearColor] }
    
    
    // Ports
    let inputCamera = NodePort<Camera>(name: "Camera", kind: .Inlet)
    let inputScene = NodePort<Object>(name: "Scene", kind: .Inlet)
    
//    let outputColorTexture  = NodePort<MTLTexture>(name: "Color Texture", kind: .Inlet)
//    let outputDepthTexture  = NodePort<MTLTexture>(name: "Depth Texture", kind: .Inlet)
    
    private let renderer:Renderer
    
    override var ports: [any AnyPort] { [inputScene, inputCamera] }
    
    required init(context:Context)
    {
        self.renderer = Renderer(context: context)
        super.init(context: context)
        
        self.renderer.clearColor = .init(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)
//        self.renderer.setClearColor(.zero)
  }
    
    override func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let object = self.inputScene.value,
           let camera = self.inputCamera.value
        {
            self.renderer.clearColor = .init( self.inputClearColor.value )
            
            renderer.draw(renderPassDescriptor: renderPassDescriptor,
                          commandBuffer: commandBuffer,
                          scene: object,
                          camera: camera)
        }
     }
    
    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {

        renderer.resize(size)

    }
}
