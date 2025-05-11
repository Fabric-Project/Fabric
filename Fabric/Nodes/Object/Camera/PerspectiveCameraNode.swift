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
    public var inputLookAt = Float3Parameter("Look At", simd_float3(repeating:0), .inputfield )

    override var inputParameters: [any Parameter] { super.inputParameters + [inputLookAt] }
    // Ports
    let outputCamera = NodePort<Camera>(name: PerspectiveCameraNode.name, kind: .Outlet)
    
    private let camera = PerspectiveCamera(position: .init(repeating: 5.0), near: 0.01, far: 500.0, fov: 30)
    
    override var ports: [any NodePortProtocol] { super.ports + [outputCamera] }
    
    required init(context:Context)
    {
        super.init(context: context)
        
        self.inputPosition.value = .init(repeating: 5.0)
        
        self.camera.lookAt(target: simd_float3(repeating: 0))
    }
    
    required init(from decoder: any Decoder) throws
    {
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

