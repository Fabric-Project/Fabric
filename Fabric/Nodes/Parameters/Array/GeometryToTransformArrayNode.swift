//
//  GeometryToTransformArrayNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//


import Foundation
import Satin
import simd
import Metal
import MetalKit

public class GeometryToTransformArrayNode : StrategyNode
{
    public override class var name:String { "Geometry Decompose" }
    public override class var nodeType:Node.NodeType { .Geometery }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Extracts a point per geometry vertex, orienting each to the vertex normal (local +Z aligned to the normal, matching the Up Orientation convention). The Transform is applied to every point. Output format selects either a single array of Transforms, or per-element Positions / Orientations / UVs." }

    public override class var strategyOptions: [any NodeStrategyOption] { GeometryToTransformMode.allCases }

    /// Reference up used when turning each vertex normal into an orientation.
    /// The roll about the normal is otherwise undetermined; a fixed world up
    /// keeps it deterministic. `simd_quatf(lookingAlong:up:)` falls back to the
    /// most perpendicular world axis when a normal is parallel to this.
    private static let referenceUp = worldUpDirection

    // The Geometry and Transform inputs are constant across output formats, so
    // they live as static ports and never churn when the format changes — only
    // the outputs are rebuilt by the strategy.
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputPort", NodePort<Geometry>(name: "Geometry", kind: .Inlet, description: "Source geometry to extract vertex positions and normals from")),
            ("inputTransform", NodePort<simd_float4x4>(name: "Transform", kind: .Inlet, description: "Transform to apply to each point")),
        ]
    }

    // Port Proxy
    public var inputPort:NodePort<Geometry> { port(named: "inputPort") }
    public var inputTransform:NodePort<simd_float4x4> { port(named: "inputTransform") }

    private static let allDynamicNames: Set<String> = [
        "outputTransforms",
        "outputPositions", "outputOrientations", "outputUVs",
    ]

    public override func rebuildPorts(forStrategy strategy: String)
    {
        let wanted: [(name: String, port: Port)]
        switch strategy
        {
        case "Transform":
            wanted =
            [
                ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "Array of per-vertex transforms: oriented to the vertex normal, positioned at the vertex, Transform applied")),
            ]

        case "Components":
            wanted =
            [
                ("outputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Outlet, description: "Per-vertex position (XYZ), Transform applied")),
                ("outputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Outlet, description: "Per-vertex quaternion orientation (X, Y, Z, W): local +Z aligned to the vertex normal, Transform's rotation applied")),
                ("outputUVs", NodePort<ContiguousArray<simd_float2>>(name: "UVs", kind: .Outlet, description: "Per-vertex texture coordinate (UV)")),
            ]

        default:
            wanted = []
        }

        let wantedNames = Set(wanted.map(\.name))
        for name in Self.allDynamicNames.subtracting(wantedNames)
        {
            if let p = findPort(named: name) { removePort(p) }
        }
        for (name, p) in wanted where findPort(named: name) == nil
        {
            addDynamicPort(p, name: name)
        }
    }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        // This is subtle: the geometry POINTER can stay identical while its
        // backing buffer changes, so we re-extract every frame rather than
        // gating on valueDidChange.
        guard let inputGeometry = self.inputPort.value else { return }

        // Resolve vertex data depending on geometry type.
        // SatinGeometry exposes a C GeometryData struct; ParametricGeometry
        // stores vertices in a public Swift array. Both contain SatinVertex.
        let vertices: [SatinVertex]
        if let satinGeo = inputGeometry as? SatinGeometry {
            // Geometry is not necessarily attached to a mesh, so its update
            // function may not have run — call it manually here.
            satinGeo.update()
            let count = Int(satinGeo.geometryData.vertexCount)
            vertices = Array(UnsafeBufferPointer(start: satinGeo.geometryData.vertexData, count: count))
        } else if let parametricGeo = inputGeometry as? ParametricGeometry {
            // generateGeometry() re-evaluates the parametric surface using the
            // current generator/ranges set by the upstream node's evaluate call.
//            parametricGeo.generateGeometry()
            vertices = parametricGeo.vertexData
        } else {
            return
        }

        let vertexCount = vertices.count
        let inputTransform = self.inputTransform.value ?? matrix_identity_float4x4

        switch self.strategy
        {
        case "Transform":
            guard let outputTransforms: NodePort<ContiguousArray<simd_float4x4>> = findPort(named: "outputTransforms") else { return }

            var output = ContiguousArray<simd_float4x4>()
            output.reserveCapacity(vertexCount)
            for vertex in vertices
            {
                // Local frame: rotation from the vertex normal, translation at
                // the vertex position. inputTransform * local places & orients
                // the whole set, so the matrix carries any input scale too.
                var local = matrix_float4x4(simd_quatf(lookingAlong: vertex.normal, up: Self.referenceUp))
                local.columns.3 = simd_float4(vertex.position, 1)
                output.append( simd_mul(inputTransform, local) )
            }
            outputTransforms.send(output)

        case "Components":
            guard let outputPositions: NodePort<ContiguousArray<simd_float3>> = findPort(named: "outputPositions"),
                  let outputOrientations: NodePort<ContiguousArray<simd_float4>> = findPort(named: "outputOrientations"),
                  let outputUVs: NodePort<ContiguousArray<simd_float2>> = findPort(named: "outputUVs")
            else { return }

            // inputTransform's rotation is constant across vertices, so extract
            // it once and compose it with each per-vertex normal orientation.
            // Scale is intentionally dropped — a point has no meaningful scale.
            let inputRotation = inputTransform.decomposedTRS.rotation

            var positions = ContiguousArray<simd_float3>(); positions.reserveCapacity(vertexCount)
            var orientations = ContiguousArray<simd_float4>(); orientations.reserveCapacity(vertexCount)
            var uvs = ContiguousArray<simd_float2>(); uvs.reserveCapacity(vertexCount)

            for vertex in vertices
            {
                let worldPosition = simd_mul(inputTransform, simd_float4(vertex.position, 1))
                let normalOrientation = simd_quatf(lookingAlong: vertex.normal, up: Self.referenceUp)

                positions.append( simd_make_float3(worldPosition) )
                orientations.append( (inputRotation * normalOrientation).normalized.vector )
                uvs.append( vertex.uv )
            }

            outputPositions.send(positions)
            outputOrientations.send(orientations)
            outputUVs.send(uvs)

        default:
            break
        }
    }
}
