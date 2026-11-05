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

    public let inputImage = NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Image to display on the image mesh")
    public let inputColor = ParameterPort(parameter: Float4Parameter("Color", .one, .zero, .one, .colorpicker, "Tint color applied to the image (RGBA)"))
    public let inputSize = ParameterPort(parameter: FloatParameter("Size", 1.0, .inputfield, "Size of the image mesh in world units"))
    public let inputSizingDimension = ParameterPort(parameter: StringParameter("Sizing Dimension", "Width", ["Width", "Height"], .dropdown, "Which dimension the Size parameter controls"))
    public let inputBlending = ParameterPort(parameter: StringParameter("Blending Mode", "Alpha", ["Disabled", "Alpha", "Additive", "Subtractive"], .dropdown, "Blending mode for combining with background pixels"))
    public let inputWriteDepth = ParameterPort(parameter: BoolParameter("Write Depth", true, .button, "When enabled, writes depth values to the depth buffer"))
    public let inputDepthTest = ParameterPort(parameter: BoolParameter("Depth Test", true, .button, "When enabled, performs depth testing against existing geometry"))
    public let inputDoubleSided = ParameterPort(parameter: BoolParameter("Double Sided", true, .button, "When enabled, the image shows from behind as well as in front"))
    public let inputCastsShadow = ParameterPort(parameter: BoolParameter("Enable Shadows", false, .button, "When enabled, the image mesh casts and receives shadows"))

    /// Visible, then the image mesh's own, then the object's others.
    override public func declaredPorts() -> [PortDeclaration]
    {
        let inherited = super.declaredPorts()
        let visible = inherited.filter { $0.key == .own("inputVisible") }
        let rest = inherited.filter { $0.key != .own("inputVisible") }

        return visible + [
            PortDeclaration(key: "inputImage", port: self.inputImage),
            PortDeclaration(key: "inputColor", port: self.inputColor),
            PortDeclaration(key: "inputSize", port: self.inputSize),
            PortDeclaration(key: "inputSizingDimension", port: self.inputSizingDimension),
            PortDeclaration(key: "inputBlending", port: self.inputBlending),
            PortDeclaration(key: "inputWriteDepth", port: self.inputWriteDepth),
            PortDeclaration(key: "inputDepthTest", port: self.inputDepthTest),
            PortDeclaration(key: "inputDoubleSided", port: self.inputDoubleSided),
            PortDeclaration(key: "inputCastsShadow", port: self.inputCastsShadow),
        ] + rest
    }

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

        if self.inputBlending.valueDidChange
        {
            self.material.blending = self.blendingMode()
        }

        if self.inputWriteDepth.valueDidChange,
           let writeDepth = self.inputWriteDepth.value
        {
            self.material.depthWriteEnabled = writeDepth
        }

        if self.inputDepthTest.valueDidChange,
           let depthTest = self.inputDepthTest.value
        {
            self.material.depthCompareFunction = depthTest ? .greaterEqual : .always
        }

        if self.inputDoubleSided.valueDidChange
        {
            self.mesh.doubleSided = self.inputDoubleSided.value ?? true
        }

        if self.inputCastsShadow.valueDidChange
        {
            let castsShadow = self.inputCastsShadow.value ?? false
            self.mesh.castShadow = castsShadow
            self.mesh.receiveShadow = castsShadow
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

    private func blendingMode() -> Blending
    {
        switch self.inputBlending.value
        {
        case "Alpha":
            return .alpha

        case "Additive":
            return .additive

        case "Subtractive":
            return .subtract

        default: return .disabled
        }
    }
}
