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
    static var type = Node.NodeType.Renderer

    // Ports
    let inputCamera = NodePort<Camera>(name: "Camera", kind: .Inlet)
    let inputScene = NodePort<Object>(name: "Scene", kind: .Inlet)
//    let cameraIn  = Port<Camera>(name: "cameraIn")
//    let lightsIn  = Port<[Light]>(name: "lightsIn")
    
    let outputColorTexture  = NodePort<MTLTexture>(name: "Color Texture", kind: .Inlet)
    let outputDepthTexture  = NodePort<MTLTexture>(name: "Depth Texture", kind: .Inlet)
    
    private let renderer:Renderer
    
    override var ports: [any AnyPort] { [inputScene, inputCamera] }
    
    required init(context:Context)
    {
        self.renderer = Renderer(context: context)
        super.init(context: context, type: .Renderer, name: RenderNode.name)
        
//        self.renderer.setClearColor(simd_float4(0.0, 1.0, 0.0, 1.0))
        self.renderer.setClearColor(.zero)
  }
    
    override func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        if let object = self.inputScene.value,
           let camera = self.inputCamera.value
        {
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
