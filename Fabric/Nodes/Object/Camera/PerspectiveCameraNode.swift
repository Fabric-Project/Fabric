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
    override public class var nodeDescription: String { "Provides a Perspective Camera for the Scene, and is the camera a Scene renders with when it has none of its own. At its defaults the view is two world units tall at the origin. Aim it with Orientation — Orientation Compose builds one from a target."}

    /// The vertical field of view every perspective camera starts with,
    /// including the one a graph gets for free.
    public static let defaultFieldOfView: Float = 30.0

    /// Where the camera sits with nothing authored: in front of the origin,
    /// far enough back that the field of view spans two world units there.
    /// The same two units the orthographic camera's view volume is tall, so
    /// the two cameras frame a scene at the origin alike.
    public static let defaultPosition = simd_float3(0, 0, 1.0 / tan(degToRad(defaultFieldOfView) / 2.0))

    /// Identity: looking along -Z, which is where a camera at the default
    /// position finds the origin. An object's orientation default is a
    /// quaternion of no length, which is not a rotation at all.
    public static let defaultOrientation = simd_float4(0, 0, 0, 1)

    /// A camera at this node's defaults, for a graph with no camera node of
    /// its own — see `GraphRenderer`. One definition, so what a graph
    /// renders does not change the moment a camera node is added to it.
    public static func makeDefaultCamera(context: Context) -> PerspectiveCamera {
        let camera = PerspectiveCamera(context: context,
                                       position: defaultPosition,
                                       near: 0.01,
                                       far: 500.0,
                                       fov: defaultFieldOfView)
        return camera
    }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        // Position, scale and orientation carry the camera's own defaults and
        // wording: an object's position default would put the camera on its
        // subject, and its scale and orientation describe an object in a
        // scene rather than the view of one.
        let ports = super.registerPorts(context: context).filter { !["inputPosition", "inputScale", "inputOrientation"].contains($0.name) }

        return  [
                    ("inputOrientation", ParameterPort(parameter:Float4Parameter("Orientation", defaultOrientation, .inputfield, "Which way the camera faces, as a quaternion (X, Y, Z, W). Identity looks along -Z")) ),
                    ("inputScale", ParameterPort(parameter:Float3Parameter("Scale", simd_float3(repeating:1), .inputfield, "Scales the camera, so the scene draws smaller as this grows")) ),
                    ("inputPosition", ParameterPort(parameter:Float3Parameter("Position", defaultPosition, .inputfield, "Position in 3D space (X, Y, Z) in world units")) ),
                ] + ports
    }
    
    
    override public var object: PerspectiveCamera?
    {
        camera
    }
    
    private lazy var camera = Self.makeDefaultCamera(context: self.context)

    override public func startExecution(renderer:GraphRenderer) throws
    {
        try super.startExecution(renderer: renderer)

        self.camera.position = self.inputPosition.value ?? Self.defaultPosition
        self.camera.scale = self.inputScale.value ?? .one
        self.camera.orientation = simd_quatf(safeVector: self.inputOrientation.value ?? Self.defaultOrientation)
    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        let shouldUpdate = super.evaluate(object: object, atTime: atTime)

        // Re-applied over the object's own, which turns a quaternion of no
        // length into NaN rather than the identity it stands for. That is
        // what a document saved against the object's zero default holds.
        if self.inputOrientation.valueDidChange
        {
            self.camera.orientation = simd_quatf(safeVector: self.inputOrientation.value ?? Self.defaultOrientation)
        }
        
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
