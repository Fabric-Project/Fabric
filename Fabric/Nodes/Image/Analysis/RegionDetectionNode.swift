//
//  RegionDetectionNode.swift
//  Fabric
//

import CoreImage
import Foundation
import Satin
import Vision
import simd

/// Detects one or more regions of interest (person, hand, or face) in an
/// image using a converted RTMDet model, for downstream pose nodes
/// (HandPoseAnalysisNode, FacePoseAnalysisNode, BodyPoseDetectionNode,
/// WholeBodyPoseDetectionNode) to crop against via their inputRegionOfInterest
/// port. Factoring detection into its own node — rather than each pose node
/// running its own internal detector — lets one detection pass feed multiple
/// pose nodes and keeps the graph composable, QC-style.
///
/// Regions are normalized [0,1], bottom-left origin (x, y, width, height) —
/// Vision's own regionOfInterest convention — so they flow into a pose
/// node's ROI input, or VNCoreMLRequest.regionOfInterest, with no conversion.
public class RegionDetectionNode: Node
{
    override public class var name: String { "Region Detection" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Detects person, hand, or face regions in an image for downstream pose nodes to crop against" }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image to detect regions in")),
            ("inputTarget", ParameterPort(parameter: StringParameter("Target", "Person", ["Person", "Hand", "Face"], .dropdown, "Which kind of region to detect"))),
            ("inputMaxDetections", ParameterPort(parameter: IntParameter("Max Detections", 1, 1, 16, .inputfield, "Maximum number of regions to detect"))),

            ("outputRegionsOfInterest", NodePort<ContiguousArray<simd_float4>>(name: "Regions", kind: .Outlet, description: "Detected regions, confidence-sorted descending, as (x, y, width, height) normalized bottom-left-origin rects")),
            ("outputRegionOfInterest", NodePort<simd_float4>(name: "Region", kind: .Outlet, description: "The single best detected region, or the full frame (0,0,1,1) if nothing was detected")),
            ("outputDetectionCount", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of regions actually detected")),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputTarget: ParameterPort<String> { port(named: "inputTarget") }
    public var inputMaxDetections: ParameterPort<Int> { port(named: "inputMaxDetections") }

    public var outputRegionsOfInterest: NodePort<ContiguousArray<simd_float4>> { port(named: "outputRegionsOfInterest") }
    public var outputRegionOfInterest: NodePort<simd_float4> { port(named: "outputRegionOfInterest") }
    public var outputDetectionCount: NodePort<Int> { port(named: "outputDetectionCount") }

    private static let fullFrameRegion = simd_float4(0, 0, 1, 1)

    private var ciContext: CIContext!
    private var lastDetections: [(rect: CGRect, confidence: Float)] = []

    override public func startExecution(renderer: GraphRenderer) throws
    {
        let options = [
            CIContextOption.cacheIntermediates: false,
            CIContextOption.highQualityDownsample: false,
            CIContextOption.workingFormat: CIFormat.RGBAh.rawValue,
            CIContextOption.workingColorSpace: nil,
            CIContextOption.outputColorSpace: nil,
        ] as? [CIContextOption: Any]

        self.ciContext = CIContext(mtlCommandQueue: self.context.commandQueue, options: options)
    }

    override public func execute(renderer: GraphRenderer, executionInfo: GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        if self.inputImage.valueDidChange, let inputImage = self.inputImage.value
        {
            let maxDetections = max(1, self.inputMaxDetections.value ?? 1)
            let targetClass = Self.modelIdentity(forTarget: self.inputTarget.value ?? "Person")
            if let detections = try? RTMDetInference.run(image: inputImage, targetClass: targetClass, maxDetections: maxDetections, ciContext: self.ciContext)
            {
                self.lastDetections = detections
            }
        }

        let regions = ContiguousArray(self.lastDetections.map { simd_float4(Float($0.rect.origin.x), Float($0.rect.origin.y), Float($0.rect.width), Float($0.rect.height)) })

        self.outputRegionsOfInterest.send(regions)
        self.outputRegionOfInterest.send(regions.first ?? Self.fullFrameRegion)
        self.outputDetectionCount.send(regions.count)
    }

    private static func modelIdentity(forTarget target: String) -> RTMModelCache.ModelIdentity
    {
        switch target
        {
        case "Hand": return .handDetector
        case "Face": return .faceDetector
        default: return .personDetector
        }
    }
}
