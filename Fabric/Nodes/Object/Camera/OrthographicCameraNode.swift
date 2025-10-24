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

public class OrthographicCameraNode : ObjectNode<OrthographicCamera>
{
    public override class var name:String { "Orthographic Camera" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Camera) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provides an Orthographic Camera for the Scene."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return  [
                    ("inputLookAt", ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield )) ),
                ] + ports
    }
    
    // Proxy Port
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    
    
    override public var object: OrthographicCamera?
    {
        camera
    }
    
    private let camera = OrthographicCamera(left: -1, right: 1, bottom: -1, top: 1, near: 0.01, far: 500.0)

    override public func startExecution(context:GraphExecutionContext)
    {
        super.startExecution(context: context)
        
        self.inputPosition.value = .init(repeating: 5.0)
        
        self.camera.lookAt(target: simd_float3(repeating: 0))
        self.camera.position = self.inputPosition.value ?? .zero
        self.camera.scale = self.inputScale.value ?? .zero
        
        let orientation = self.inputOrientation.value ?? .zero
        self.camera.orientation = simd_quatf(angle: orientation.w,
                                             axis: simd_float3(x: orientation.x,
                                                               y: orientation.y,
                                                               z: orientation.z) )
    }

    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        let shouldUpdate = super.evaluate(object: object, atTime: atTime)

        // This needs to fire every frame
        self.camera.lookAt(target: self.inputLookAt.value ?? .zero)
        
        return shouldUpdate
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let shouldUpdate = self.evaluate(object: self.object, atTime: context.timing.time)
        
//        if shouldUpdate
//        {
//            self.outputCamera.send(self.camera)
//        }
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        let aspect = size.width / size.height

        self.camera.left = -aspect / 2.0
        self.camera.right = aspect / 2.0
    }
}

