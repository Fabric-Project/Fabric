//
//  ImageMeshNode.swift
//  Fabric
//
//  Created by Toby Harris + Claude Opus 4.6 on 3/1/26.
//

import Foundation
import Satin
import simd
import Metal

class ImageMeshNode: BaseRenderableNode<Mesh>
{
    override public class var name: String { "Image Mesh" }
    override public class var nodeType: Node.NodeType { .Object(objectType: .Mesh) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Renders an image on a plane with automatic aspect-ratio sizing" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        let visible = ports.filter { $0.name == "inputVisible" }
        let rest = ports.filter { $0.name != "inputVisible" }

        return visible + [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Image to display on the image mesh")),
            ("inputColor", ParameterPort(parameter: Float4Parameter("Color", .one, .zero, .one, .colorpicker, "Tint color applied to the image (RGBA)"))),
            ("inputSize", ParameterPort(parameter: FloatParameter("Size", 1.0, .inputfield, "Size of the image mesh in world units"))),
            ("inputSizingDimension", ParameterPort(parameter: StringParameter("Sizing Dimension", "Width", ["Width", "Height"], .dropdown, "Which dimension the Size parameter controls"))),
        ] + rest
    }

    // Port accessors
    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputColor: ParameterPort<simd_float4> { port(named: "inputColor") }
    public var inputSize: ParameterPort<Float> { port(named: "inputSize") }
    public var inputSizingDimension: ParameterPort<String> { port(named: "inputSizingDimension") }

    override public var object: Mesh? {
        return self.mesh
    }

    private let mesh: Mesh
    private let geometry:PlaneGeometry
    private let material:BasicTextureMaterial

    public required init(context: Context)
    {
        self.geometry = PlaneGeometry(context:context,width: 1, height: 1, orientation: .xy)
//        self.geometry = QuadGeometry(context: context)
        self.material = BasicTextureMaterial(context:context)
        self.mesh = Mesh(context:context, geometry: self.geometry, material: self.material)

        super.init(context: context)

        self.material.setup()
        self.mesh.doubleSided = true
    }

    public required init(from decoder: any Decoder) throws
    {
        guard let context = decoder.context?.documentContext as? Context else {
            fatalError("Failed to decode Context from decoder")
        }
        
        self.geometry = PlaneGeometry(context:context,width: 1, height: 1, orientation: .xy)
//        self.geometry = QuadGeometry(context: context)// PlaneGeometry(context:context,width: 1, height: 1, orientation: .xy)
        self.material = BasicTextureMaterial(context:context)
        self.mesh = Mesh(context:context, geometry: self.geometry, material: self.material)

        try super.init(from: decoder)

        self.material.setup()
        self.mesh.doubleSided = true
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.inputImage.valueDidChange
        {
            self.material.texture = self.inputImage.value?.texture
            self.material.textureTransform = self.inputImage.value?.textureTransform ?? matrix_identity_float4x4
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
            
            let size = self.inputSize.value ?? 1.0
            let aspect: Float

            if let image = self.inputImage.value
            {
                aspect = Float(image.presentationSize.width / image.presentationSize.height)
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

        let _ = self.evaluate(object: mesh, atTime: executionInfo.timing.time)
    }
}
