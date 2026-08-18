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
    override public class var name:String { "Perspective Camera" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Camera) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provides a Perspective Camera for the Scene. This is the camera used if none are in the graph. Add to control position, field of view etc."}

    /// The vertical field of view every perspective camera starts with,
    /// including the one a graph gets for free.
    public static let defaultFieldOfView: Float = 30.0

    /// Where the camera sits with nothing authored: in front of the origin,
    /// far enough back that the field of view spans two world units there.
    /// The same two units the orthographic camera's view volume is tall, so
    /// the two cameras frame a scene at the origin alike.
    public static let defaultPosition = simd_float3(0, 0, 1.0 / tan(degToRad(defaultFieldOfView) / 2.0))

    /// A camera at this node's defaults, for a graph with no camera node of
    /// its own — see `GraphRenderer`. One definition, so what a graph
    /// renders does not change the moment a camera node is added to it.
    public static func makeDefaultCamera(context: Context) -> PerspectiveCamera {
        let camera = PerspectiveCamera(context: context,
                                       position: defaultPosition,
                                       near: 0.01,
                                       far: 500.0,
                                       fov: defaultFieldOfView)
        camera.lookAt(target: .zero)
        return camera
    }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        // Position carries the camera's own default rather than an object's
        // origin, which would put the camera on its subject.
        let ports = super.registerPorts(context: context).filter { $0.name != "inputPosition" }

        return  [
                    ("inputLookAt", ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield, "Target position the camera points toward")) ),
                    ("inputPosition", ParameterPort(parameter:Float3Parameter("Position", defaultPosition, .inputfield, "Position in 3D space (X, Y, Z) in world units")) ),
                ] + ports
    }
    
    // Proxy Port
    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    
    override public var object: PerspectiveCamera?
    {
        camera
    }
    
    private lazy var camera = Self.makeDefaultCamera(context: self.context)

    override public func startExecution(renderer:GraphRenderer) throws
    {
        try super.startExecution(renderer: renderer)

        self.camera.position = self.inputPosition.value ?? Self.defaultPosition
        self.camera.lookAt(target: self.inputLookAt.value ?? .zero)
        self.camera.scale = self.inputScale.value ?? .one
        
        let orientation = self.inputOrientation.value ?? .zero
        self.camera.orientation = simd_quatf(vector:orientation)
    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        let shouldUpdate = super.evaluate(object: object, atTime: atTime)

        // This needs to fire every frame
        self.camera.lookAt(target: self.inputLookAt.value ?? .zero)
        
        return shouldUpdate
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let _ = self.evaluate(object: self.camera, atTime: executionInfo.timing.time)
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.camera.aspect = size.width / size.height
    }
  
}
