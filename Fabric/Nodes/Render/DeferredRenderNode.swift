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

public class DeferredRenderNode : Node, NodeProtocol
{
    public static let name = "Deferred Render"
    public static var nodeType = Node.NodeType.Renderer
    
    // Parameters
    public let inputResolution:Int2Parameter
    public let inputClearColor:Float4Parameter

    public override var inputParameters: [any Parameter] { super.inputParameters + [inputResolution, inputClearColor] }
    
    // Ports
    public let inputCamera: NodePort<Camera>
    public let inputScene: NodePort<Object>

    public let outputColorTexture:NodePort<EquatableTexture>
    public let outputDepthTexture:NodePort<EquatableTexture>

    // Ensure we always render!
    public override var isDirty:Bool { get {  true  } set { } }
    
    private let renderer:Renderer
    
    public override var ports: [any NodePortProtocol] { super.ports +  [inputCamera, inputScene, outputColorTexture, outputDepthTexture] }
    
    public required init(context:Context)
    {
        self.renderer = Renderer(context: context, frameBufferOnly:false)
        self.renderer.depthStoreAction = .store
        self.renderer.depthLoadAction = .clear
        self.renderer.size.width = 1920
        self.renderer.size.height = 1080

        self.inputResolution = Int2Parameter("Resolution", simd_int2(x:1920, y:1080), simd_int2(x:1, y:1), simd_int2(x:8192, y:8192), .inputfield)
        self.inputClearColor = Float4Parameter("Clear Color", simd_float4(repeating:0), .colorpicker)

        self.inputCamera = NodePort<Camera>(name: "Camera", kind: .Inlet)
        self.inputScene =  NodePort<Object>(name: "Scene", kind: .Inlet)
        self.outputColorTexture = NodePort<EquatableTexture>(name: "Color Texture", kind: .Outlet)
        self.outputDepthTexture = NodePort<EquatableTexture>(name: "Depth Texture", kind: .Outlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputClearColorParam
        case inputResolution
        case inputCameraPort
        case inputScenePort
        case outputColorTexturePort
        case outputDepthTexturePort
    }
    
    public required init(from decoder: any Decoder) throws
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

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputCamera = try container.decode(NodePort<Camera>.self , forKey:.inputCameraPort)
        self.inputScene =  try container.decode(NodePort<Object>.self , forKey:.inputScenePort)

        self.outputColorTexture = try container.decode(NodePort<EquatableTexture>.self , forKey:.outputColorTexturePort)
        self.outputDepthTexture =  try container.decode(NodePort<EquatableTexture>.self , forKey:.outputDepthTexturePort)

        self.inputClearColor = try container.decode(Float4Parameter.self , forKey:.inputClearColorParam)
        self.inputResolution = try container.decode(Int2Parameter.self, forKey: .inputResolution)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputClearColor, forKey: .inputClearColorParam)
        try container.encode(self.inputResolution, forKey: .inputResolution)
        try container.encode(self.inputCamera, forKey: .inputCameraPort)
        try container.encode(self.inputScene, forKey: .inputScenePort)
        try container.encode(self.outputColorTexture, forKey: .outputColorTexturePort)
        try container.encode(self.outputDepthTexture, forKey: .outputDepthTexturePort)

        try super.encode(to: encoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let object = self.inputScene.value,
           let camera = self.inputCamera.value
        {
            let rpd1 = MTLRenderPassDescriptor()

            if (self.renderer.size.width != Float(self.inputResolution.value.x)) ||  (self.renderer.size.height != Float(self.inputResolution.value.y))
            {
                self.renderer.resize( (width:Float(self.inputResolution.value.x), height:Float(self.inputResolution.value.y) ) )
            }
           
            
            self.renderer.clearColor = .init( self.inputClearColor.value )
                        
            renderer.draw(renderPassDescriptor: rpd1,
                          commandBuffer: commandBuffer,
                          scene: object,
                          camera: camera)
            
            if let texture = renderer.colorTexture
            {
                self.outputColorTexture.send( EquatableTexture(texture: texture) )
            }
            else
            {
                self.outputColorTexture.send( nil )

            }
            
            if let texture = renderer.depthTexture
            {
                self.outputDepthTexture.send( EquatableTexture(texture: texture) )
            }
            else
            {
                self.outputDepthTexture.send( nil )
            }
        }
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        //        renderer.resize(size)
    }
}
