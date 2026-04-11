//
//  SVGPathRendererNode.swift
//  Fabric
//
//  Rasterize an SVG path d string to a texture via CoreGraphics.
//

import Foundation
import Satin
import simd
import Metal
import CoreGraphics

public class SVGPathRendererNode: Node
{
    public override class var name: String { "SVG Path Renderer" }
    public override class var nodeType: Node.NodeType { .Image(imageType: .Generator) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Rasterize an SVG path d string to a texture via CoreGraphics" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputPathData", ParameterPort(parameter: StringParameter("Path Data", "", .inputfield, "SVG path d attribute string"))),

            ("inputWidth", ParameterPort(parameter: IntParameter("Width", 512, 1, 8192, .inputfield, "Output image width in pixels"))),
            ("inputHeight", ParameterPort(parameter: IntParameter("Height", 512, 1, 8192, .inputfield, "Output image height in pixels"))),
            ("inputViewBoxX", ParameterPort(parameter: FloatParameter("ViewBox X", 0, .inputfield, "Source viewport origin X"))),
            ("inputViewBoxY", ParameterPort(parameter: FloatParameter("ViewBox Y", 0, .inputfield, "Source viewport origin Y"))),
            ("inputViewBoxW", ParameterPort(parameter: FloatParameter("ViewBox W", 100, .inputfield, "Source viewport width"))),
            ("inputViewBoxH", ParameterPort(parameter: FloatParameter("ViewBox H", 100, .inputfield, "Source viewport height"))),

            ("inputFillColor", ParameterPort(parameter: Float4Parameter("Fill Color", simd_float4(0, 0, 0, 1), .colorpicker, "Fill color (RGBA)"))),
            ("inputFillEnabled", ParameterPort(parameter: BoolParameter("Fill", true, .toggle, "Enable fill"))),
            ("inputStrokeColor", ParameterPort(parameter: Float4Parameter("Stroke Color", simd_float4(1, 1, 1, 1), .colorpicker, "Stroke color (RGBA)"))),
            ("inputStrokeEnabled", ParameterPort(parameter: BoolParameter("Stroke", false, .toggle, "Enable stroke"))),
            ("inputStrokeWidth", ParameterPort(parameter: FloatParameter("Stroke Width", 1.0, .inputfield, "Stroke width in SVG units"))),

            ("outputTexturePort", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Rendered path image")),
        ]
    }

    public var inputPathData: ParameterPort<String> { port(named: "inputPathData") }
    public var inputWidth: ParameterPort<Int> { port(named: "inputWidth") }
    public var inputHeight: ParameterPort<Int> { port(named: "inputHeight") }
    public var inputViewBoxX: ParameterPort<Float> { port(named: "inputViewBoxX") }
    public var inputViewBoxY: ParameterPort<Float> { port(named: "inputViewBoxY") }
    public var inputViewBoxW: ParameterPort<Float> { port(named: "inputViewBoxW") }
    public var inputViewBoxH: ParameterPort<Float> { port(named: "inputViewBoxH") }
    public var inputFillColor: ParameterPort<simd_float4> { port(named: "inputFillColor") }
    public var inputFillEnabled: ParameterPort<Bool> { port(named: "inputFillEnabled") }
    public var inputStrokeColor: ParameterPort<simd_float4> { port(named: "inputStrokeColor") }
    public var inputStrokeEnabled: ParameterPort<Bool> { port(named: "inputStrokeEnabled") }
    public var inputStrokeWidth: ParameterPort<Float> { port(named: "inputStrokeWidth") }
    public var outputTexturePort: NodePort<FabricImage> { port(named: "outputTexturePort") }

    @ObservationIgnored private var cachedPathHash: Int?
    @ObservationIgnored private var cachedCGPath: CGPath?

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let anyChanged = self.ports.contains(where: { $0.valueDidChange })
        guard anyChanged else { return }

        guard let pathString = inputPathData.value, !pathString.isEmpty else {
            outputTexturePort.send(nil)
            return
        }

        let width = max(1, inputWidth.value ?? 512)
        let height = max(1, inputHeight.value ?? 512)

        let hash = pathString.hashValue
        let cgPath: CGPath
        if hash == cachedPathHash, let cached = cachedCGPath {
            cgPath = cached
        } else {
            guard let parsed = SVGPathConverter.pathFromSVGData(pathString) else {
                outputTexturePort.send(nil)
                return
            }
            cgPath = parsed
            cachedPathHash = hash
            cachedCGPath = parsed
        }

        let viewBox = simd_float4(
            inputViewBoxX.value ?? 0,
            inputViewBoxY.value ?? 0,
            inputViewBoxW.value ?? 100,
            inputViewBoxH.value ?? 100
        )

        let op = SVGTextureRenderer.PathRenderOp(
            cgPath: cgPath,
            fillColor: inputFillColor.value ?? simd_float4(0, 0, 0, 1),
            fillEnabled: inputFillEnabled.value ?? true,
            strokeColor: inputStrokeColor.value ?? simd_float4(1, 1, 1, 1),
            strokeEnabled: inputStrokeEnabled.value ?? false,
            strokeWidth: inputStrokeWidth.value ?? 1.0
        )

        let device = context.graphRenderer!.context.device
        guard let image = SVGTextureRenderer.render(
            operations: [op],
            viewBox: viewBox,
            width: width, height: height,
            device: device
        ) else {
            outputTexturePort.send(nil)
            return
        }

        outputTexturePort.send(image)
    }
}
