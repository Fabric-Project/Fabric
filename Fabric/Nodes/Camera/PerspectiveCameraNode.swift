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

class PerspectiveCameraNode : Node, NodeProtocol
{
    static var type = Node.NodeType.Camera
    
    static let name = "Perspective Camera"
    
    // Ports
    let outputCamera = NodePort<Camera>(name: PerspectiveCameraNode.name, kind: .Outlet)
    
    private let camera = PerspectiveCamera(position: [0, 0, 5], near: 0.1, far: 100.0, fov: 30)
    
    override var ports: [any AnyPort] { [outputCamera] }
    
    required init(context:Context)
    {
        super.init(context: context,
                   type: PerspectiveCameraNode.type,
                   name: PerspectiveCameraNode.name)
        
        //        self.camera.position = simd_float3(0, 0, 5)
        self.camera.lookAt(target: simd_float3(repeating: 0))
    }
    
    override  func evaluate(atTime:TimeInterval,
                            renderPassDescriptor: MTLRenderPassDescriptor,
                            commandBuffer: MTLCommandBuffer)
    {
        self.outputCamera.send(self.camera)
    }
    
    override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        camera.aspect = size.width / size.height
    }
}

