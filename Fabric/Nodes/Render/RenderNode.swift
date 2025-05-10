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
    let inputClearColor = Float4Parameter("Clear Color", simd_float4(repeating:0), .colorpicker)

    override var inputParameters: [any Parameter] { super.inputParameters + [inputClearColor] }
    
    // Ensure we always render!
    override var isDirty:Bool { get {  true  } set { } }
    
    // Ports
    let inputCamera: NodePort<Camera>
    let inputScene: NodePort<Object>
    
    private let renderer:Renderer
    
    override var ports: [any AnyPort] { super.ports +  [inputCamera, inputScene] }
    
    enum CodingKeys : String, CodingKey
    {
        case inputCameraPort
        case inputScenePort
    }
    
    required init(context:Context)
    {
        self.renderer = Renderer(context: context)
        self.inputCamera = NodePort<Camera>(name: "Camera", kind: .Inlet)
        self.inputScene =  NodePort<Object>(name: "Scene", kind: .Inlet)
        
        super.init(context: context)
    }
    
    required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.renderer = Renderer(context: decodeContext.documentContext, frameBufferOnly:false)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputCamera = try container.decode(NodePort<Camera>.self , forKey:.inputCameraPort)
        self.inputScene =  try container.decode(NodePort<Object>.self , forKey:.inputScenePort)
        
        try super.init(from:decoder)
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputCamera, forKey: .inputCameraPort)
        try container.encode(self.inputScene, forKey: .inputScenePort)
        
        try super.encode(to: encoder)
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
