//
//  WorldTextBillboardNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

class WorldTextBillboardNode: BaseRenderableNode<Mesh>
{
    override public class var name: String { "World Text Billboard" }
    override public class var nodeType: Node.NodeType { .Object(objectType: .Mesh) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Renders a text image on a world-space billboard that can face the active camera" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let visible = ports.filter { $0.name == "inputVisible" }
        let rest = ports.filter { $0.name != "inputVisible" }

        return visible + [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Text image to display on the billboard")),
            ("inputColor", ParameterPort(parameter: Float4Parameter("Color", .one, .zero, .one, .colorpicker, "Tint color applied to the text image (RGBA)"))),
            ("inputSize", ParameterPort(parameter: FloatParameter("Size", 1.0, .inputfield, "Billboard size in world units"))),
            ("inputSizingDimension", ParameterPort(parameter: StringParameter("Sizing Dimension", "Width", ["Width", "Height"], .dropdown, "Which dimension the Size parameter controls"))),
            ("inputFaceCamera", ParameterPort(parameter: BoolParameter("Face Camera", true, .button, "When enabled, billboard faces the active camera each frame"))),
            ("inputLockYAxis", ParameterPort(parameter: BoolParameter("Lock Y Axis", true, .button, "When enabled, billboard rotates only around Y to face camera"))),
        ] + rest
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputColor: ParameterPort<simd_float4> { port(named: "inputColor") }
    public var inputSize: ParameterPort<Float> { port(named: "inputSize") }
    public var inputSizingDimension: ParameterPort<String> { port(named: "inputSizingDimension") }
    public var inputFaceCamera: ParameterPort<Bool> { port(named: "inputFaceCamera") }
    public var inputLockYAxis: ParameterPort<Bool> { port(named: "inputLockYAxis") }

    override public var object: Mesh? {
        guard self.inputImage.value != nil else { return nil }
        return self.mesh
    }

    private let mesh: Mesh
    private let geometry = PlaneGeometry(width: 1, height: 1, orientation: .xy)
    private let material = BasicTextureMaterial()

    public required init(context: Context)
    {
        self.mesh = Mesh(geometry: self.geometry, material: self.material)

        super.init(context: context)

        self.material.setup()
        self.mesh.doubleSided = true
    }

    public required init(from decoder: any Decoder) throws
    {
        self.mesh = Mesh(geometry: self.geometry, material: self.material)

        try super.init(from: decoder)

        self.material.setup()
        self.mesh.doubleSided = true
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputImage.valueDidChange
        {
            self.material.texture = self.inputImage.value?.texture
            self.material.flipped = !(self.inputImage.value?.isFlipped ?? false)
        }

        if self.inputColor.valueDidChange,
           let color = self.inputColor.value
        {
            self.material.color = color
        }

        if self.inputImage.valueDidChange
            || self.inputSize.valueDidChange
            || self.inputSizingDimension.valueDidChange
        {
            self.updateGeometrySize()
        }

        let _ = self.evaluate(object: self.mesh, atTime: context.timing.time)

        let activeCamera = context.graphRenderer?.currentCamera
            ?? self.graph.flatMap { Graph.getFirstCamera(graph: $0) }

        if self.inputFaceCamera.value ?? true,
           let camera = activeCamera
        {
            self.applyBillboardOrientation(camera: camera)
        }
    }

    private func updateGeometrySize()
    {
        let size = self.inputSize.value ?? 1.0
        let aspect: Float

        if let texture = self.inputImage.value?.texture
        {
            aspect = Float(texture.width) / Float(texture.height)
        }
        else
        {
            aspect = 1.0
        }

        if self.inputSizingDimension.value == "Height"
        {
            self.geometry.height = size
            self.geometry.width = size * aspect
        }
        else
        {
            self.geometry.width = size
            self.geometry.height = size / aspect
        }
    }

    private func applyBillboardOrientation(camera: Camera)
    {
        let meshWorldPosition = self.mesh.worldPosition
        let cameraWorldPosition = camera.worldPosition

        var toCamera = cameraWorldPosition - meshWorldPosition
        if self.inputLockYAxis.value ?? true
        {
            toCamera.y = 0
        }

        let distanceSquared = simd_length_squared(toCamera)
        guard distanceSquared > 0.000001 else { return }

        let forward = simd_normalize(toCamera)
        var up = Satin.worldUpDirection

        if abs(simd_dot(forward, up)) > 0.999
        {
            up = SIMD3<Float>(1, 0, 0)
        }

        let right = simd_normalize(simd_cross(up, forward))
        let correctedUp = simd_normalize(simd_cross(forward, right))
        let orientationBasis = simd_float3x3(columns: (right, correctedUp, forward))
        self.mesh.worldOrientation = simd_quatf(orientationBasis)
    }
}
