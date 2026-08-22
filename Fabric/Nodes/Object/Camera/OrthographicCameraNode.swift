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
    override public class var nodeDescription: String { "Provides an Orthographic Camera for the Scene. Its view is two world units tall and as many wide as the render target's aspect, before Scale. Aim it with Orientation — Orientation Compose builds one from a target."}

    /// Where the camera sits with nothing authored. In front of the origin
    /// looking at it, so the default view is the XY plane face on. Distance
    /// is free of the framing here — an orthographic view volume does not
    /// narrow with it — and only has to clear the near plane.
    public static let defaultPosition = simd_float3(0, 0, 2)

    /// Identity: looking along -Z, which is where a camera at the default
    /// position finds the origin. An object's orientation default is a
    /// quaternion of no length, which is not a rotation at all.
    public static let defaultOrientation = simd_float4(0, 0, 0, 1)

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        // Position, scale and orientation carry the camera's own defaults and
        // wording: an object's position default would put the camera on its
        // subject, and its scale and orientation describe an object in a
        // scene rather than the view of one.
        let ports = super.registerPorts(context: context).filter { !["inputPosition", "inputScale", "inputOrientation"].contains($0.name) }

        return  [
                    ("inputOrientation", ParameterPort(parameter:Float4Parameter("Orientation", defaultOrientation, .inputfield, "Which way the camera faces, as a quaternion (X, Y, Z, W). Identity looks along -Z")) ),
                    ("inputScale", ParameterPort(parameter:Float3Parameter("Scale", simd_float3(repeating:1), .inputfield, "Scales the view volume, so the scene draws smaller as this grows: two world units tall at 1")) ),
                    ("inputPosition", ParameterPort(parameter:Float3Parameter("Position", defaultPosition, .inputfield, "Position in 3D space (X, Y, Z) in world units")) ),
                ] + ports
    }
    
    override public var object: OrthographicCamera?
    {
        camera
    }
    
    private lazy var camera = OrthographicCamera(context:self.context, left: -1, right: 1, bottom: -1, top: 1, near: 0.01, far: 500.0)

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
        let _ = self.evaluate(object: self.object, atTime: executionInfo.timing.time)
    }
    
    public override func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        // Two world units tall, and as many wide as the aspect allows, so a
        // world unit measures the same across as it does down. Half of the
        // aspect would not: the vertical extent is the ±1 the camera is
        // constructed with, which no resize changes.
        let aspect = size.width / size.height

        self.camera.left = -aspect
        self.camera.right = aspect
    }
}
