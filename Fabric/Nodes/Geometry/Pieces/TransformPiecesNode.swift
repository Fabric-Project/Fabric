//
//  TransformPiecesNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// Poses the pieces of a geometry with one transform per piece, on the GPU. Each piece is a
/// skinning joint, so a transform change only rewrites one matrix per piece in this node's own
/// joint palette: vertex buffers are never touched, and the output is re-sent only when the
/// geometry changes. A piece is drawn with its parents' transforms composed onto its own, and
/// last frame's matrices give the velocity output real per-piece motion.
public class TransformPiecesNode: Node
{
    public override class var name: String { "Transform Pieces" }
    public override class var nodeType: Node.NodeType { .Geometery }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Poses the pieces of a geometry (text split into pieces, the output of a cutting plugin) on the GPU with one transform per piece, in piece order: an animator's Transforms or any Transform array. Each piece also moves with its parent pieces' transforms, so a shorter array from earlier in a chain moves whole groups. Only the matrices are uploaded when the Transforms change. Missing transforms leave their pieces at rest; extras are ignored. Motion reaches the velocity output for motion blur." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        super.registerPorts(context: context) +
        [
            ("inputGeometry", NodePort<Geometry>(name: "Geometry", kind: .Inlet, description: "The pieces to pose: geometry with pieces, or another Transform Pieces output (its rest pieces are used)")),
            ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet, description: "One transform per piece, in piece order, parents first: a model-space delta from rest")),
            ("outputGeometry", NodePort<Geometry>(name: "Geometry", kind: .Outlet, description: "The pieces, posed; draw with any Mesh and material")),
        ]
    }

    public var inputGeometry: NodePort<Geometry> { port(named: "inputGeometry") }
    public var inputTransforms: NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputTransforms") }
    public var outputGeometry: NodePort<Geometry> { port(named: "outputGeometry") }

    private var posedPieces: PosedPieces?
    private var poseStatuses: [NodeStatus] = []

    override public func deriveStatuses() -> [NodeStatus] { poseStatuses }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let geometryChanged = self.inputGeometry.valueDidChange
        guard geometryChanged || self.inputTransforms.valueDidChange else { return }
        let transforms = Array(self.inputTransforms.value ?? [])

        if geometryChanged
        {
            guard let geometry = self.inputGeometry.value else
            {
                self.posedPieces = nil
                self.poseStatuses = []
                self.outputGeometry.send(nil)
                return
            }
            // A posed view (another Transform Pieces output) is posed from its rest source.
            let rest = geometry.skinningSource
            guard rest.pieces != nil else
            {
                // No pieces to pose: pass it through unchanged.
                self.posedPieces = nil
                self.poseStatuses = [.warning("Connect geometry with pieces, such as text split into pieces or a cutting node's output; other geometry passes through unchanged.")]
                self.outputGeometry.send(geometry)
                return
            }
            let posed = PosedPieces(source: rest, transforms: transforms)
            self.posedPieces = posed
            self.outputGeometry.send(posed)
        }
        else if let posedPieces = self.posedPieces
        {
            // Uploaded on Satin's next update; the output stays the same object.
            posedPieces.transforms = transforms
        }

        var statuses: [NodeStatus] = []
        if let pieceCount = self.posedPieces?.pieces?.count, !transforms.isEmpty, transforms.count != pieceCount
        {
            statuses = [.warning("\(transforms.count) transforms for \(pieceCount) pieces: pieces without a transform stay at rest, and extra transforms are ignored.")]
        }
        self.poseStatuses = statuses
    }
}
