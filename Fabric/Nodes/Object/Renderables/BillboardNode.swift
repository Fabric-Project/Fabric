//
//  BillboardNode.swift
//  Fabric
//
//  Created by Toby Harris + Claude Opus 4.6 on 3/1/26.
//

import Foundation
import Satin
import simd
import Metal

class BillboardNode: BaseRenderableNode<Mesh>
{
    override public class var name: String { "Billboard" }
    override public class var nodeType: Node.NodeType { .Object(objectType: .Mesh) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Renders an image on a plane with automatic aspect-ratio sizing" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Image to display on the billboard")),
            ("inputSize", ParameterPort(parameter: FloatParameter("Size", 1.0, .inputfield, "Size of the billboard in world units"))),
            ("inputSizingDimension", ParameterPort(parameter: StringParameter("Sizing Dimension", "Width", ["Width", "Height"], .dropdown, "Which dimension the Size parameter controls"))),
        ] + ports
    }

    // Port accessors
    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputSize: ParameterPort<Float> { port(named: "inputSize") }
    public var inputSizingDimension: ParameterPort<String> { port(named: "inputSizingDimension") }

    override public var object: Mesh? {
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

        if self.inputImage.valueDidChange
            || self.inputSize.valueDidChange
            || self.inputSizingDimension.valueDidChange
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

        let _ = self.evaluate(object: mesh, atTime: context.timing.time)
    }
}
