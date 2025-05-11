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

class PerspectiveCameraNode : BaseObjectNode, NodeProtocol
{
    static var nodeType = Node.NodeType.Camera
    static let name = "Perspective Camera"
    
    // Params
    public var inputLookAt:Float3Parameter
    override var inputParameters: [any Parameter] { super.inputParameters + [inputLookAt] }

    // Ports
    let outputCamera:NodePort<Camera>
    override var ports: [any NodePortProtocol] { super.ports + [outputCamera] }

    private let camera = PerspectiveCamera(position: .init(repeating: 5.0), near: 0.01, far: 500.0, fov: 30)

    required init(context:Context)
    {
        self.inputLookAt = Float3Parameter("Look At", simd_float3(repeating:0), .inputfield )
        self.outputCamera = NodePort<Camera>(name: PerspectiveCameraNode.name, kind: .Outlet)
        
        super.init(context: context)
        
        self.inputPosition.value = .init(repeating: 5.0)
        
        self.camera.lookAt(target: simd_float3(repeating: 0))
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputLookAtParameter
        case outputCameraPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputLookAt, forKey: .inputLookAtParameter)
        try container.encode(self.outputCamera, forKey: .outputCameraPort)
        
        try super.encode(to: encoder)
    }
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputLookAt = try container.decode(Float3Parameter.self, forKey: .inputLookAtParameter)
        self.outputCamera = try container.decode(NodePort<Camera>.self, forKey: .outputCameraPort)
        
        try super.init(from: decoder)
    }

    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(object: self.camera, atTime: atTime)
        
        self.camera.lookAt(target: self.inputLookAt.value)
        
        self.outputCamera.send(self.camera)
    }
    
    override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        camera.aspect = size.width / size.height
    }
}

