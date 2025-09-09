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

public class RenderNode : Node, NodeProtocol
{
    public static let name = "Scene Render"
    public static var nodeType = Node.NodeType.Renderer

    // Parameters
    public let inputClearColor:Float4Parameter
    public override var inputParameters: [any Parameter] { super.inputParameters + [inputClearColor] }
    
    // Ports
    public let inputCamera: NodePort<Camera>
    public let inputScene: NodePort<Object>
    public override var ports: [any NodePortProtocol] { [inputScene, inputCamera] + super.ports }

    // Ensure we always render!
    public override var isDirty:Bool { get {  true  } set { } }
    
    private let renderer:Renderer
       
    public required init(context:Context)
    {
        self.renderer = Renderer(context: context, stencilStoreAction: .store, frameBufferOnly:false)

        self.inputClearColor = Float4Parameter("Clear Color", simd_float4(repeating:0), .colorpicker)

        self.inputCamera = NodePort<Camera>(name: "Camera", kind: .Inlet)
        self.inputScene =  NodePort<Object>(name: "Scene", kind: .Inlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputClearColorParam
        case inputCameraPort
        case inputScenePort
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.renderer = Renderer(context: decodeContext.documentContext, stencilStoreAction: .store, frameBufferOnly:false)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputCamera = try container.decode(NodePort<Camera>.self , forKey:.inputCameraPort)
        self.inputScene =  try container.decode(NodePort<Object>.self , forKey:.inputScenePort)

        self.inputClearColor = try container.decode(Float4Parameter.self , forKey:.inputClearColorParam)

        try super.init(from:decoder)
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputClearColor, forKey: .inputClearColorParam)
        try container.encode(self.inputCamera, forKey: .inputCameraPort)
        try container.encode(self.inputScene, forKey: .inputScenePort)
        
        try super.encode(to: encoder)
    }
    
    public override func execute(context:GraphExecutionContext,
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
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
    }
}
