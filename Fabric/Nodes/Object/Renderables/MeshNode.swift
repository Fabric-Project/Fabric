//
//  MeshNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

public class MeshNode : BaseRenderableNode<Mesh>
{
    override public class var name:String { "Mesh" }
    override public class var nodeDescription: String { "Combine a Geometry and Material into a renderable Mesh, with control over shadows, face culling, double-sided rendering, and the anchor point of the geometry's bounding box." }
    override public class var nodeType:Node.NodeType { .Object(objectType: .Mesh) }

    /// 9-point anchor options. `Center` is the default and is a true
    /// no-op — no bounds are sampled, no offset is applied. Picking
    /// any other value shifts the mesh so the chosen point on its
    /// axis-aligned bounding box lands at the `Position` input
    /// (Z always uses bounds-center).
    private static let anchorOptions: [String] = [
        "Center",
        "Top Left", "Top", "Top Right",
        "Left", "Right",
        "Bottom Left", "Bottom", "Bottom Right",
    ]

    // Register ports, in order of appearance
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {

        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputGeometry",  NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet, description: "Geometry mesh to render")),
            ("inputMaterial",  NodePort<Material>(name: "Material", kind: .Inlet, description: "Material to apply to the geometry")),
            ("inputAnchor",    ParameterPort(parameter: StringParameter("Anchor", "Center", Self.anchorOptions, .dropdown, "Anchor point on the geometry's bounding box that aligns with Position. Center is free (no bounds calc); any other value samples bounds when the geometry input changes. NOTE: bounds are not re-sampled per-frame, so animated geometry whose vertex buffer is rewritten under a stable reference will keep its initial anchor offset until the geometry input itself changes.") ) ),
            ("inputCastsShadow",  ParameterPort(parameter: BoolParameter("Enable Shadows", true, .button, "When enabled, the mesh casts and receives shadows") ) ),
            ("inputDoubleSided",  ParameterPort(parameter: BoolParameter("Double Sided", false, .button, "When enabled, renders both front and back faces") ) ),
            ("inputCullingMode",  ParameterPort(parameter: StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown, "Which faces to cull during rendering") ) ),
        ]
    }

    // Ergonomic access (no storage assignment needed)
    public var inputGeometry: NodePort<SatinGeometry>   { port(named: "inputGeometry") }
    public var inputMaterial: NodePort<Material>   { port(named: "inputMaterial") }
    public var inputAnchor: ParameterPort<String>   { port(named: "inputAnchor") }
    public var inputCastsShadow: ParameterPort<Bool>   { port(named: "inputCastsShadow") }
    public var inputDoubleSided: ParameterPort<Bool>   { port(named: "inputDoubleSided") }
    public var inputCullingMode: ParameterPort<String>   { port(named: "inputCullingMode") }

    /// Cached anchor *point* in geometry-local coordinates (not the
    /// offset — the raw point on the AABB). `mesh.position` is set to
    /// `inputPosition.value − orientation.act(scale * cachedAnchorPoint)`
    /// so the chosen point is a true pivot for both scale and rotation:
    /// scaling 2× with anchor = Top Left grows the mesh down-right
    /// while keeping the top-left corner fixed at Position.
    /// Stays at `.zero` while the anchor is `Center`, so the default
    /// path never touches `geometry.bounds`.
    private var cachedAnchorPoint: simd_float3 = .zero

    
    override public var object:Mesh? {
        
        // This is tricky - we want to output nil if we have no inputGeometry  / inputMaterial from upstream ports
        if let _ = self.inputGeometry.value,
           let _ = self.inputMaterial.value
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
    
    override public func teardown()
    {
        super.teardown()
        self.mesh = nil
        self.inputGeometry.value = nil
        self.inputMaterial.value = nil
    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)

        // If subclass has object that isnt a mesh, but its own scene graph..
        // We need to handle that in the parent :(
        guard let mesh = object as? Mesh else { return shouldOutput }

        if self.inputCastsShadow.valueDidChange,
           let castShadow = self.inputCastsShadow.value,
           let receiveShadow = self.inputCastsShadow.value
        {
            mesh.castShadow = castShadow
            mesh.receiveShadow = receiveShadow
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

        // Anchor pivot: recompute the anchor *point* when geometry or
        // anchor selection changes, then re-apply mesh.position whenever
        // any input that contributes to the pivoted-position formula
        // changes. The cached point stays `.zero` for anchor=Center, so
        // the formula collapses to `mesh.position = base` — no rotation
        // / scale work in the common case.
        let geometryChanged = self.inputGeometry.valueDidChange
        let anchorChanged = self.inputAnchor.valueDidChange
        if geometryChanged || anchorChanged {
            self.recomputeAnchorPoint()
            shouldOutput = true
        }
        if geometryChanged || anchorChanged
            || self.inputPosition.valueDidChange
            || self.inputScale.valueDidChange
            || self.inputOrientation.valueDidChange
        {
            self.applyAnchoredPosition(to: mesh)
        }

        return shouldOutput
    }

    /// Refresh `cachedAnchorPoint` from the current geometry's bounds
    /// and the anchor selection. Reads `geometry.bounds` only when
    /// the anchor is something other than Center.
    private func recomputeAnchorPoint()
    {
        let anchor = self.inputAnchor.value ?? "Center"
        guard anchor != "Center", let geometry = self.inputGeometry.value else {
            self.cachedAnchorPoint = .zero
            return
        }
        // Geometries not attached to a mesh haven't had `update()`
        // called yet; ensure the buffer reflects the current vertex
        // data before reading bounds.
        geometry.update()
        let bounds = geometry.bounds
        let cx = (bounds.min.x + bounds.max.x) * 0.5
        let cy = (bounds.min.y + bounds.max.y) * 0.5
        let cz = (bounds.min.z + bounds.max.z) * 0.5
        switch anchor {
        case "Top Left":     self.cachedAnchorPoint = simd_float3(bounds.min.x, bounds.max.y, cz)
        case "Top":          self.cachedAnchorPoint = simd_float3(cx,            bounds.max.y, cz)
        case "Top Right":    self.cachedAnchorPoint = simd_float3(bounds.max.x, bounds.max.y, cz)
        case "Left":         self.cachedAnchorPoint = simd_float3(bounds.min.x, cy,            cz)
        case "Right":        self.cachedAnchorPoint = simd_float3(bounds.max.x, cy,            cz)
        case "Bottom Left":  self.cachedAnchorPoint = simd_float3(bounds.min.x, bounds.min.y, cz)
        case "Bottom":       self.cachedAnchorPoint = simd_float3(cx,            bounds.min.y, cz)
        case "Bottom Right": self.cachedAnchorPoint = simd_float3(bounds.max.x, bounds.min.y, cz)
        default:             self.cachedAnchorPoint = .zero
        }
    }

    /// Set `mesh.position` so the cached anchor point lands at
    /// `inputPosition` for any combination of scale and orientation.
    ///
    /// The mesh's vertex transform is `T(pos) · R · S · v`. To make
    /// `anchor` behave as a pivot we want
    /// `T(userPos) · R · S · (v − anchor)`, which expands back to the
    /// existing form by setting `pos = userPos − R·S·anchor`. With
    /// `cachedAnchorPoint == .zero` (anchor = Center) the rotation /
    /// scale terms drop out and the result is just `userPos`.
    private func applyAnchoredPosition(to mesh: Mesh)
    {
        let base = self.inputPosition.value ?? .zero
        if self.cachedAnchorPoint == .zero {
            mesh.position = base
            return
        }
        let scale = self.inputScale.value ?? simd_float3(repeating: 1)
        let orientation = self.inputOrientation.value.map { simd_quatf(vector: $0).normalized }
            ?? simd_quatf(real: 1, imag: .zero)
        let scaledAnchor = self.cachedAnchorPoint * scale
        let rotatedAnchor = orientation.act(scaledAnchor)
        mesh.position = base - rotatedAnchor
    }
    
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if
            (self.inputGeometry.valueDidChange
             || self.inputMaterial.valueDidChange)
        {
            
            if let geometry = self.inputGeometry.value,
               let material = self.inputMaterial.value

            {
                if let mesh = mesh
                {
                    let geometryJustAttached = mesh.geometry !== geometry
                    let materialJustAttached = mesh.material !== material

                    if geometryJustAttached
                    {
                        let windingOrder = mesh.windingOrder
                        mesh.geometry = geometry
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
                    let mesh = Mesh(geometry: geometry, material: material)
                    self.applyCurrentMeshState(mesh,
                                               materialJustAttached: true)

                    self.mesh = mesh
                }
            }
            else
            {
                self.mesh = nil
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
        mesh.scale = self.inputScale.value ?? simd_float3(repeating: 1)
        let orientation = self.inputOrientation.value ?? .zero
        mesh.orientation = simd_quatf(vector: orientation).normalized
        // Recompute the anchor point against the freshly-attached
        // geometry, then write position with scale + rotation factored
        // in so the chosen anchor truly pivots.
        self.recomputeAnchorPoint()
        self.applyAnchoredPosition(to: mesh)

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
    
    func cullMode() -> MTLCullMode
    {
        switch self.inputCullingMode.value
        {
        case "Front":
            return .front
        case "Back":
            return .back
            
        default: return .none
        }
    }
}
