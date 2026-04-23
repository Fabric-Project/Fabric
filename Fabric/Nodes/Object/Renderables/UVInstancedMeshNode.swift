//
//  UVInstancedMeshNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class UVInstancedMeshNode : BaseRenderableNode<Mesh>
{
    override public class var name: String { "UV Instanced Mesh" }
    override public class var nodeDescription: String { "Renders N copies of Geometry, each positioned by Transforms[i] and with UVs transformed by UV Transform2Ds[i]. Bridges to an eventual Satin v2 per-instance UV-transform API: today the composite geometry is baked on the CPU each time inputs change; later the same ports will forward directly to Satin's native per-instance UV transforms. Port shape is forward-compatible so graphs survive the migration." }
    override public class var nodeType: Node.NodeType { .Object(objectType: .Mesh) }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputGeometry", NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet, description: "Template geometry replicated for every instance")),
            ("inputMaterial", NodePort<Material>(name: "Material", kind: .Inlet, description: "Material shared across all instances")),
            ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet, description: "Per-instance model matrices. Output instance count is this array's length.")),
            ("inputUVTransform2Ds", NodePort<ContiguousArray<simd_float4x4>>(name: "UV Transform2Ds", kind: .Inlet, description: "Per-instance 2D transforms applied to the template's UVs before sampling. Shorter arrays pad with their last element; unconnected defaults to identity per instance.")),
            ("inputCastsShadow", ParameterPort(parameter: BoolParameter("Enable Shadows", true, .button, "When enabled, the mesh casts and receives shadows"))),
            ("inputDoubleSided", ParameterPort(parameter: BoolParameter("Double Sided", false, .button, "When enabled, renders both front and back faces"))),
            ("inputCullingMode", ParameterPort(parameter: StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown, "Which faces to cull during rendering"))),
        ]
    }

    // Port proxies
    public var inputGeometry: NodePort<SatinGeometry> { port(named: "inputGeometry") }
    public var inputMaterial: NodePort<Material> { port(named: "inputMaterial") }
    public var inputTransforms: NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputTransforms") }
    public var inputUVTransform2Ds: NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputUVTransform2Ds") }
    public var inputCastsShadow: ParameterPort<Bool> { port(named: "inputCastsShadow") }
    public var inputDoubleSided: ParameterPort<Bool> { port(named: "inputDoubleSided") }
    public var inputCullingMode: ParameterPort<String> { port(named: "inputCullingMode") }

    override public var object: Mesh? {
        if let _ = self.inputGeometry.value,
           let _ = self.inputMaterial.value,
           let transforms = self.inputTransforms.value,
           !transforms.isEmpty
        {
            return mesh
        }
        return nil
    }

    private var mesh: Mesh? = nil
    {
        didSet
        {
            // Relying on side effects - this triggers
            self.graph?.syncNodesToScene(removingObject: oldValue)
        }
    }

    private var bakedGeometry: BakedUVGeometry? = nil

    override public func teardown()
    {
        super.teardown()
        self.mesh = nil
        self.bakedGeometry = nil
        self.inputGeometry.value = nil
        self.inputMaterial.value = nil
    }

    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)

        guard let mesh = object as? Mesh else { return shouldOutput }

        if self.inputCastsShadow.valueDidChange,
           let castShadow = self.inputCastsShadow.value
        {
            mesh.castShadow = castShadow
            mesh.receiveShadow = castShadow
            shouldOutput = true
        }

        if self.inputCullingMode.valueDidChange
        {
            mesh.cullMode = self.cullMode()
            shouldOutput = true
        }

        if self.inputDoubleSided.valueDidChange
        {
            mesh.doubleSided = self.inputDoubleSided.value ?? false
            shouldOutput = true
        }

        return shouldOutput
    }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let bakeInputsChanged = self.inputGeometry.valueDidChange
            || self.inputTransforms.valueDidChange
            || self.inputUVTransform2Ds.valueDidChange

        let materialChanged = self.inputMaterial.valueDidChange

        if bakeInputsChanged || materialChanged
        {
            if let template = self.inputGeometry.value,
               let material = self.inputMaterial.value,
               let transforms = self.inputTransforms.value,
               !transforms.isEmpty
            {
                if bakeInputsChanged
                {
                    let uvTransforms = self.inputUVTransform2Ds.value ?? ContiguousArray<simd_float4x4>()
                    let baked = Self.bakeGeometry(
                        template: template,
                        transforms: transforms,
                        uvTransforms: uvTransforms
                    )

                    if let existing = self.bakedGeometry
                    {
                        existing.replace(data: baked)
                    }
                    else
                    {
                        self.bakedGeometry = BakedUVGeometry(data: baked)
                    }
                }

                guard let baked = self.bakedGeometry else { return }

                if let mesh = mesh
                {
                    let geometryJustAttached = mesh.geometry !== baked
                    let materialJustAttached = mesh.material !== material

                    if geometryJustAttached
                    {
                        let windingOrder = mesh.windingOrder
                        mesh.geometry = baked
                        mesh.windingOrder = windingOrder
                    }

                    if materialJustAttached
                    {
                        mesh.material = material
                    }

                    self.applyCurrentMeshState(mesh,
                                               materialJustAttached: materialJustAttached)
                }
                else
                {
                    let newMesh = Mesh(geometry: baked, material: material)
                    self.applyCurrentMeshState(newMesh,
                                               materialJustAttached: true)

                    self.mesh = newMesh
                }
            }
            else
            {
                self.mesh = nil
                self.bakedGeometry = nil
            }
        }

        if let mesh = mesh
        {
            let _ = self.evaluate(object: mesh, atTime: context.timing.time)
        }
    }

    private func applyCurrentMeshState(_ mesh: Mesh,
                                       materialJustAttached: Bool)
    {
        mesh.lookAt(target: simd_float3(repeating: 0))
        mesh.visible = self.inputVisible.value ?? true
        mesh.renderOrder = self.inputRenderOrder.value ?? 0
        mesh.renderPass = self.inputRenderPass.value ?? 0
        mesh.position = self.inputPosition.value ?? .zero
        mesh.scale = self.inputScale.value ?? simd_float3(repeating: 1)

        let orientation = self.inputOrientation.value ?? .zero
        mesh.orientation = simd_quatf(vector: orientation).normalized

        let castShadow = self.inputCastsShadow.value ?? true
        mesh.castShadow = castShadow
        mesh.receiveShadow = castShadow
        mesh.cullMode = self.cullMode()
        mesh.doubleSided = self.inputDoubleSided.value ?? false

        if materialJustAttached,
           let material = mesh.material
        {
            material.castShadow = castShadow
            material.receiveShadow = castShadow
        }
    }

    private func cullMode() -> MTLCullMode
    {
        switch self.inputCullingMode.value
        {
        case "Front":
            return .front
        case "Back":
            return .back
        default:
            return .none
        }
    }

    // MARK: - Geometry baking

    /// Concatenates N copies of the template geometry, applying the per-instance
    /// model transform to positions and normals (via combineAndTransformGeometryData)
    /// and the per-instance UV transform to UVs in a follow-up pass. Returns a
    /// freshly-allocated GeometryData whose pointers the caller owns.
    private static func bakeGeometry(
        template: SatinGeometry,
        transforms: ContiguousArray<simd_float4x4>,
        uvTransforms: ContiguousArray<simd_float4x4>
    ) -> GeometryData
    {
        // Ensure template's geometryData is materialised.
        template.update()
        var templateData = template.geometryData

        var composite = createGeometryData()

        let fallbackUV = uvTransforms.last ?? matrix_identity_float4x4

        for i in 0..<transforms.count
        {
            let transform = transforms[i]
            let uvMatrix = i < uvTransforms.count ? uvTransforms[i] : fallbackUV

            let startVertex = Int(composite.vertexCount)
            combineAndTransformGeometryData(&composite, &templateData, transform)
            let endVertex = Int(composite.vertexCount)

            // Transform UVs of the newly appended vertices.
            if endVertex > startVertex, composite.vertexData != nil
            {
                for j in startVertex..<endVertex
                {
                    let vertexPtr = composite.vertexData.advanced(by: j)
                    let uv = vertexPtr.pointee.uv
                    let transformed = simd_mul(uvMatrix, simd_float4(uv.x, uv.y, 0, 1))
                    vertexPtr.pointee.uv = simd_float2(transformed.x, transformed.y)
                }
            }
        }

        return composite
    }
}

// MARK: - Baked geometry helper

/// A SatinGeometry whose underlying data is supplied externally (via
/// `replace(data:)`) rather than generated from parameters. Ownership of the
/// supplied GeometryData transfers in: the geometry frees it on next replace
/// or on deinit.
private class BakedUVGeometry : SatinGeometry
{
    private var _pendingData: GeometryData?

    init(data: GeometryData)
    {
        self._pendingData = data
        super.init()
    }

    required init(from decoder: any Decoder) throws
    {
        fatalError("BakedUVGeometry is not Codable")
    }

    override func generateGeometryData() -> GeometryData
    {
        if let data = _pendingData
        {
            _pendingData = nil
            return data
        }
        return createGeometryData()
    }

    func replace(data: GeometryData)
    {
        if var previous = _pendingData
        {
            freeGeometryData(&previous)
        }
        _pendingData = data
        _updateData = true
    }

    deinit
    {
        if var pending = _pendingData
        {
            freeGeometryData(&pending)
        }
    }
}
