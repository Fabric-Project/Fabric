//
//  SpotLightNode.swift
//  Fabric
//
//  Created by OpenAI on 5/11/26.
//

import Foundation
import Satin
import simd
import Metal

public class SpotLightNode : ObjectNode<SpotLight>
{
    public override class var name:String { "Spot Light" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Object(objectType: .Light) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Adds a Spot Light to the scene with optional cookie or projector image support."}

    private static let projectionModeOptions = ["Mask", "Color"]
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return  [
            ("inputLookAt", ParameterPort(parameter:Float3Parameter("Look At", simd_float3(repeating:0), .inputfield, "Target position the light points toward")) ),
            ("inputColor", ParameterPort(parameter:Float3Parameter("Color", simd_float3(repeating:1), .inputfield, "RGB color of the light")) ),
            ("inputIntensity", ParameterPort(parameter: FloatParameter("Intensity", 1.0, 0.0, 300.0, .slider, "Brightness multiplier for the light"))),
            ("inputRadius", ParameterPort(parameter: FloatParameter("Radius", 10.0, 0.0, 1000.0, .slider, "Distance at which the light falls off to zero"))),
            ("inputAngleInner", ParameterPort(parameter: FloatParameter("Inner Angle", 15.0, 0.0, 89.0, .slider, "Fully lit cone angle in degrees"))),
            ("inputAngleOuter", ParameterPort(parameter: FloatParameter("Outer Angle", 25.0, 0.0, 89.0, .slider, "Falloff cone angle in degrees"))),
            ("inputProjectionImage", NodePort<FabricImage>(name: "Projection Image", kind: .Inlet, description: "Optional image used as a spotlight cookie or projector texture")),
            ("inputProjectionMode", ParameterPort(parameter: StringParameter("Projection Mode", "Mask", Self.projectionModeOptions, .dropdown, "How the projection image is applied to the scene"))),
            ("inputShadowStrength", ParameterPort(parameter: FloatParameter("Shadow Strength", 0.5, 0.0, 2.0, .slider, "Opacity of cast shadows (0 = invisible, higher values darken more)"))),
            ("inputShadowRadius", ParameterPort(parameter: FloatParameter("Shadow Radius", 1.0, 0.0, 10.0, .slider, "Blur radius for soft shadow edges"))),
            ("inputShadowBias", ParameterPort(parameter: FloatParameter("Shadow Bias", 0.0001, 0.0, 0.01, .slider, "Offset to prevent shadow acne artifacts"))),
        ] + ports
    }

    public var inputLookAt:ParameterPort<simd_float3> { port(named: "inputLookAt") }
    public var inputColor: ParameterPort<simd_float3> { port(named: "inputColor") }
    public var inputIntensity: ParameterPort<Float> { port(named: "inputIntensity") }
    public var inputRadius: ParameterPort<Float> { port(named: "inputRadius") }
    public var inputAngleInner: ParameterPort<Float> { port(named: "inputAngleInner") }
    public var inputAngleOuter: ParameterPort<Float> { port(named: "inputAngleOuter") }
    public var inputProjectionImage: NodePort<FabricImage> { port(named: "inputProjectionImage") }
    public var inputProjectionMode: ParameterPort<String> { port(named: "inputProjectionMode") }
    public var inputShadowStrength: ParameterPort<Float> { port(named: "inputShadowStrength") }
    public var inputShadowRadius: ParameterPort<Float> { port(named: "inputShadowRadius") }
    public var inputShadowBias: ParameterPort<Float> { port(named: "inputShadowBias") }

    public override var object: SpotLight? {
        return light
    }

    private lazy var light: SpotLight = SpotLight(
        context: self.context,
        color: simd_float3(1.0, 1.0, 1.0),
        intensity: 1.0,
        radius: 10.0,
        angleInner: 15.0,
        angleOuter: 25.0
    )

    override public func startExecution(renderer:GraphRenderer)
    throws
    {
        self.setupDefaultLight()
    }

    private func setupDefaultLight()
    {
        self.light.lookAt(target: .zero, up: Satin.worldUpDirection)
        self.light.castShadow = true
        self.light.shadow.resolution = (1024, 1024)
        self.light.shadow.bias = 0.0001
        self.light.shadow.strength = 0.5
        self.light.shadow.radius = 1.0
    }

    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)

        if self.inputColor.valueDidChange,
           let color = self.inputColor.value
        {
            self.light.color = color
            shouldOutput = true
        }

        if self.inputIntensity.valueDidChange,
           let intensity = self.inputIntensity.value
        {
            self.light.intensity = intensity
            shouldOutput = true
        }

        if self.inputRadius.valueDidChange,
           let radius = self.inputRadius.value
        {
            self.light.radius = radius
            shouldOutput = true
        }

        if self.inputAngleInner.valueDidChange || self.inputAngleOuter.valueDidChange
        {
            self.applyClampedSpotAngles()
            shouldOutput = true
        }

        if self.inputProjectionImage.valueDidChange
        {
            self.applyProjectionImage()
            shouldOutput = true
        }

        if self.inputProjectionMode.valueDidChange
        {
            self.light.projectionMode = self.resolvedProjectionMode()
            shouldOutput = true
        }

        if self.inputShadowStrength.valueDidChange,
           let shadowStrength =  self.inputShadowStrength.value
        {
            self.light.shadow.strength = shadowStrength
            shouldOutput = true
        }

        if self.inputShadowRadius.valueDidChange,
           let shadowRadius = self.inputShadowRadius.value
        {
            self.light.shadow.radius = shadowRadius
            shouldOutput = true
        }

        if self.inputShadowBias.valueDidChange,
           let shadowBias = self.inputShadowBias.value
        {
            self.light.shadow.bias = shadowBias
            shouldOutput = true
        }

        self.light.lookAt(target: self.inputLookAt.value ?? .zero)

        return shouldOutput
    }

    private func applyClampedSpotAngles()
    {
        let rawInnerAngle = self.inputAngleInner.value ?? self.light.angleInner
        let rawOuterAngle = self.inputAngleOuter.value ?? self.light.angleOuter

        let clampedInnerAngle = min(max(rawInnerAngle, 0.0), 89.0)
        let clampedOuterAngle = min(max(rawOuterAngle, clampedInnerAngle), 89.0)

        self.light.angleInner = clampedInnerAngle
        self.light.angleOuter = clampedOuterAngle
    }

    private func applyProjectionImage()
    {
        let image = self.inputProjectionImage.value
        self.light.projectionTexture = image?.texture
        self.light.projectionTransform = image.map {
            let transform = $0.textureTransform
            return simd_float3x3(simd_float3(transform.columns.0.x, transform.columns.0.y, 0),
                                 simd_float3(transform.columns.1.x, transform.columns.1.y, 0),
                                 simd_float3(transform.columns.3.x, transform.columns.3.y, 1))
        } ?? matrix_identity_float3x3
    }

    private func resolvedProjectionMode() -> SpotLightProjectionMode
    {
        switch self.inputProjectionMode.value {
        case "Color":
            return .color
        default:
            return .mask
        }
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let _ = self.evaluate(object: self.light, atTime: executionInfo.timing.time)
    }
}
