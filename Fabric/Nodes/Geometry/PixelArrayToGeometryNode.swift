//
//  PixelArrayToGeometryNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/25/25.
//
import Satin
import Foundation
import simd
import Metal

/// The named and functional inverse of "Points From Geometry": rebuilds a
/// point geometry from per-vertex Positions, Orientations and UVs. Each input
/// array produces one vertex; the orientation's local +Z becomes the vertex
/// normal (the inverse of how "Points From Geometry" derives an orientation
/// from a normal via `simd_quatf(lookingAlong:up:)`).
///
/// Orientation and UV are optional so the common 2D case stays trivial: with
/// only Positions wired, every normal defaults to +Z (facing the viewer) and
/// UVs default to a planar [0,1] projection of the points' XY bounds.
public class PixelArrayToGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Geometry From Points" }
    public override class var nodeDescription: String { "Rebuilds a point geometry from per-vertex Positions, Orientations and UVs — the inverse of Points From Geometry. Orientation and UV are optional: normals default to +Z and UVs to a planar projection of the points." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        // Drop the base's Triangle-defaulted Primitive port; this node emits a
        // point cloud, so Point is the sensible default.
        let ports = super.registerPorts(context: context).filter { $0.name != "inputPrimitiveType" }

        return [
            ("inputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Inlet, description: "Per-vertex position (XYZ). One vertex per element.")),
            ("inputOrientations", NodePort<ContiguousArray<simd_float4>>(name: "Orientations", kind: .Inlet, description: "Optional per-vertex quaternion orientation (X, Y, Z, W); its local +Z becomes the vertex normal. Defaults to identity (normal +Z) when unconnected.")),
            ("inputUVs", NodePort<ContiguousArray<simd_float2>>(name: "UVs", kind: .Inlet, description: "Optional per-vertex texture coordinate. Defaults to a planar [0,1] projection of the XY bounds when unconnected.")),
            ("inputPrimitiveType", ParameterPort(parameter: StringParameter("Primitive", "Point", ["Point", "Line", "Line Strip", "Triangle", "Triangle Strip"], .dropdown, "Rendering primitive type for the geometry mesh"))),
        ] + ports
    }

    public var inputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "inputPositions") }
    public var inputOrientations: NodePort<ContiguousArray<simd_float4>> { port(named: "inputOrientations") }
    public var inputUVs: NodePort<ContiguousArray<simd_float2>> { port(named: "inputUVs") }

    public override var geometry: PointCloudGeometry { _geometry }

    private lazy var _geometry = PointCloudGeometry(context: self.context,
                                                    positions: [],
                                                    normals: [],
                                                    uvs: [])

    override public func evaluate(geometry: SatinGeometry, atTime: TimeInterval) -> Bool
    {
        // Base applies primitive-type changes / dirty state to the current geometry.
        var shouldOutput = super.evaluate(geometry: geometry, atTime: atTime)

        if self.inputPositions.valueDidChange
            || self.inputOrientations.valueDidChange
            || self.inputUVs.valueDidChange
        {
            if let positions = self.inputPositions.value, !positions.isEmpty
            {
                let count = positions.count

                // Orientation → normal. Unconnected (or empty) broadcasts the
                // identity quaternion, so every normal falls back to +Z.
                let orientations = (self.inputOrientations.value ?? [])
                    .paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))
                var normals = ContiguousArray<simd_float3>(); normals.reserveCapacity(count)
                for q in orientations
                {
                    normals.append(simd_quatf.upDirection(from: q))
                }

                // UVs: use the wired array (padded) if present, otherwise a
                // sensible planar default derived from the XY bounds.
                let uvs: ContiguousArray<simd_float2>
                if let wiredUVs = self.inputUVs.value, !wiredUVs.isEmpty
                {
                    uvs = ContiguousArray(wiredUVs.paddedToLast(count: count, fallback: .zero))
                }
                else
                {
                    uvs = Self.planarUVs(for: positions)
                }

                let g = PointCloudGeometry(context: self.context,
                                           positions: positions,
                                           normals: normals,
                                           uvs: uvs)
                g.primitiveType = self.primitiveType()
                self._geometry = g
                shouldOutput = true
            }
        }

        return shouldOutput
    }

    /// Planar [0,1] UVs from the XY bounds of the points — the sensible default
    /// for the flat 2D case. A degenerate (zero-extent) axis maps to 0.
    private static func planarUVs(for positions: ContiguousArray<simd_float3>) -> ContiguousArray<simd_float2>
    {
        var minXY = simd_float2(positions[0].x, positions[0].y)
        var maxXY = minXY
        for p in positions
        {
            minXY = simd.min(minXY, simd_float2(p.x, p.y))
            maxXY = simd.max(maxXY, simd_float2(p.x, p.y))
        }
        let range = maxXY - minXY

        var uvs = ContiguousArray<simd_float2>(); uvs.reserveCapacity(positions.count)
        for p in positions
        {
            let u = range.x > 1e-6 ? (p.x - minXY.x) / range.x : 0
            let v = range.y > 1e-6 ? (p.y - minXY.y) / range.y : 0
            uvs.append(simd_float2(u, v))
        }
        return uvs
    }
}


/// A `SatinGeometry` whose vertices are supplied directly as parallel
/// position / normal / uv arrays, rendered as unconnected points (no indices).
public final class PointCloudGeometry : SatinGeometry
{
    var positions: ContiguousArray<simd_float3>
    var normals: ContiguousArray<simd_float3>
    var uvs: ContiguousArray<simd_float2>

    init(context: Context,
         positions: ContiguousArray<simd_float3>,
         normals: ContiguousArray<simd_float3>,
         uvs: ContiguousArray<simd_float2>)
    {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        super.init(context: context)
    }

    override public func generateGeometryData() -> GeometryData
    {
        var data = createGeometryData()
        let count = self.positions.count
        guard count > 0 else { return data }

        // malloc so the C `freeGeometryData` (which calls free) can release it.
        // On allocation failure, fall back to the empty geometry rather than crash.
        guard let rawVertexData = malloc(count * MemoryLayout<SatinVertex>.stride) else { return data }
        let vertexData = rawVertexData.bindMemory(to: SatinVertex.self, capacity: count)
        for i in 0 ..< count
        {
            vertexData[i] = SatinVertex(position: self.positions[i],
                                        normal: self.normals[i],
                                        uv: self.uvs[i])
        }

        data.vertexCount = Int32(count)
        data.vertexData = vertexData
        // No indices: points are independent vertices.
        return data
    }
}
