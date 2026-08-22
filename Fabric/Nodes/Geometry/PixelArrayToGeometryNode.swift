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

/// The named and functional inverse of "Geometry Decompose": builds a
/// point geometry from per-vertex Positions, Orientations and UVs. Each input
/// array produces one vertex; the orientation's local +Z becomes the vertex
/// normal (the inverse of how "Geometry Decompose" derives an orientation
/// from a normal via `simd_quatf(lookingAlong:up:)`).
///
/// Orientation and UV are optional so the common 2D case stays trivial: with
/// only Positions wired, every normal defaults to +Z (facing the viewer) and
/// UVs default to a planar [0,1] projection of the points' XY bounds.
public class PixelArrayToGeometryNode : BaseGeometryNode
{
    public override class var name:String { "Geometry Compose" }
    public override class var nodeDescription: String { "Builds a point geometry from per-vertex Positions, Orientations and UVs — the inverse of Geometry Decompose. Orientation and UV are optional: normals default to +Z and UVs to a planar projection of the points." }

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

    private lazy var _geometry: PointCloudGeometry = {
        let g = PointCloudGeometry(context: self.context, positions: [], normals: [], uvs: [])
        g.mutability = .dynamicData
        return g
    }()

    override public func evaluate(geometry: Geometry, atTime: TimeInterval) -> Bool
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

                // Orientation → normal (the orientation's local +Z). With
                // Orientations unconnected — the common 2D case — every normal
                // is +Z, so skip the per-element quaternion work entirely.
                let normals: ContiguousArray<simd_float3>
                if let wiredOrientations = self.inputOrientations.value, !wiredOrientations.isEmpty
                {
                    let orientations = wiredOrientations.paddedToLast(count: count, fallback: simd_float4(0, 0, 0, 1))
                    var ns = ContiguousArray<simd_float3>(); ns.reserveCapacity(count)
                    for q in orientations
                    {
                        ns.append(simd_quatf.upDirection(from: q))
                    }
                    normals = ns
                }
                else
                {
                    normals = ContiguousArray(repeating: simd_float3(0, 0, 1), count: count)
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

                self._geometry.setData(positions: positions, normals: normals, uvs: uvs)
                self._geometry.primitiveType = self.primitiveType()
                shouldOutput = true
            }
        }

        return shouldOutput
    }

    /// Planar [0,1] UVs from the XY bounds of the points — the sensible default
    /// for the flat 2D case. A degenerate (zero-extent) axis maps to 0.
    private static func planarUVs(for positions: ContiguousArray<simd_float3>) -> ContiguousArray<simd_float2>
    {
        // No simd call reduces across an array (simd_reduce_* fold the lanes of
        // one vector), so the bounds scan is a loop — as in Satin's own
        // computeBoundsFromVertices. Reduce over the full float3 to stay in SIMD
        // and avoid a per-element shuffle; the unused z lane comes for free.
        var minP = positions[0]
        var maxP = positions[0]
        for p in positions
        {
            minP = simd.min(minP, p)
            maxP = simd.max(maxP, p)
        }

        let minXY = simd_float2(minP.x, minP.y)
        let range = simd_float2(maxP.x, maxP.y) - minXY

        // Hoist the zero-extent guard out of the loop and turn the per-point
        // divide into one vector multiply by the precomputed reciprocal.
        let invRange = simd_float2(range.x > 1e-6 ? 1 / range.x : 0,
                                   range.y > 1e-6 ? 1 / range.y : 0)

        var uvs = ContiguousArray<simd_float2>(); uvs.reserveCapacity(positions.count)
        for p in positions
        {
            uvs.append((simd_float2(p.x, p.y) - minXY) * invRange)
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

    /// Update vertex data in-place rather than creating a new geometry object.
    /// Sets `_updateData = true` so the next `update()` call regenerates GPU buffers.
    func setData(positions: ContiguousArray<simd_float3>,
                 normals: ContiguousArray<simd_float3>,
                 uvs: ContiguousArray<simd_float2>)
    {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        _updateData = true
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
