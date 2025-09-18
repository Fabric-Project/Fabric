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

public class OrthographicCameraNode : BaseObjectNode, NodeProtocol
{
    public static var nodeType = Node.NodeType.Camera
    public static let name = "Orthographic Camera"
    
    // Params
    public var inputLookAt:Float3Parameter
    public override var inputParameters: [any Parameter] { [inputLookAt] + super.inputParameters}

    // Ports
    public let outputCamera:NodePort<Camera>
    public override var ports: [any NodePortProtocol] { [outputCamera] + super.ports }

    private let camera = OrthographicCamera(left: -1, right: 1, bottom: -1, top: 1, near: 0.01, far: 500.0)

    public required init(context:Context)
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
    }

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.evaluate(object: self.camera, atTime: context.timing.time)
        
        if self.inputLookAt.valueDidChange
        {
            self.camera.lookAt(target: self.inputLookAt.value)
        }
        self.outputCamera.send(self.camera)
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        let aspect = size.width / size.height

        self.camera.left = -aspect / 2.0
        self.camera.right = aspect / 2.0
    }
}

