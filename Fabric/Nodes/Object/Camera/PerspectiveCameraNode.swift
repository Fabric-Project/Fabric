//
//  PerspectiveCameraNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

public class PerspectiveCameraNode : ObjectNode<PerspectiveCamera>
{
    public override class var name:String { "Perspective Camera" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Camera) }

    // Params
    public var inputLookAt:Float3Parameter
    public override var inputParameters: [any Parameter] {  [inputLookAt] + super.inputParameters}

    // Ports
    public let outputCamera:NodePort<Camera>
    public override var ports: [AnyPort] { [outputCamera] + super.ports }

    override public var object: PerspectiveCamera?
    {
        camera
    }
    
    private let camera = PerspectiveCamera(position: .init(repeating: 5.0), near: 0.01, far: 500.0, fov: 30)

    
    public required init(context:Context)
    {
        self.inputLookAt = Float3Parameter("Look At", simd_float3(repeating:0), .inputfield )
        self.outputCamera = NodePort<Camera>(name: PerspectiveCameraNode.name, kind: .Outlet)
                
        super.init(context: context)
        
        self.inputPosition.value = .init(repeating: 5.0)
        

        self.object?.lookAt(target: simd_float3(repeating: 0))
        self.object?.position = self.inputPosition.value
        self.object?.scale = self.inputScale.value

        self.object?.orientation = simd_quatf(angle: self.inputOrientation.value.w,
                                        axis: simd_float3(x: self.inputOrientation.value.x,
                                                          y: self.inputOrientation.value.y,
                                                          z: self.inputOrientation.value.z) )
        
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputLookAtParameter
        case outputCameraPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputLookAt, forKey: .inputLookAtParameter)
        try container.encode(self.outputCamera, forKey: .outputCameraPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputLookAt = try container.decode(Float3Parameter.self, forKey: .inputLookAtParameter)
        self.outputCamera = try container.decode(NodePort<Camera>.self, forKey: .outputCameraPort)
        
        try super.init(from: decoder)
        
        self.camera.lookAt(target: self.inputLookAt.value)
    }

    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        let shouldUpdate = super.evaluate(object: object, atTime: atTime)

        // This needs to fire every frame
        self.camera.lookAt(target: self.inputLookAt.value)
        
        return shouldUpdate
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let shouldUpdate = self.evaluate(object: self.camera, atTime: context.timing.time)
        
        if shouldUpdate
        {
            self.outputCamera.send(self.camera)
        }
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.camera.aspect = size.width / size.height
    }
}

