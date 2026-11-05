//
//  PieceInfoNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin
import simd

/// A geometry's per-piece data, as arrays in piece order, for building transforms with
/// animators or Fabric's own array nodes.
public class PieceInfoNode: Node
{
    public override class var name: String { "Piece Info" }
    public override class var nodeType: Node.NodeType { .Geometery }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Outputs a geometry's per-piece data as arrays in piece order, parents first, in its local rest coordinates: rest centers, true volumes, each piece's parent and its generation (how many parents it has above it). Feed Centers (and Volumes) to an animator, or build your own Transforms from them for Transform Pieces." }

    public let inputGeometry = NodePort<Geometry>(name: "Geometry", kind: .Inlet, description: "Geometry with pieces, or a Transform Pieces output (its rest pieces are used)")
    public let outputPieceCount = NodePort<Int>(name: "Piece Count", kind: .Outlet, description: "Number of pieces of every generation: the length of a Transforms array for Transform Pieces")
    public let outputCenters = NodePort<ContiguousArray<simd_float3>>(name: "Centers", kind: .Outlet, description: "Each piece's pivot at rest")
    public let outputVolumes = NodePort<ContiguousArray<Float>>(name: "Volumes", kind: .Outlet, description: "Each piece's volume; a parent's is the sum of its children's. Flat pieces, such as 2D text, have none and report 0")
    public let outputParentIndices = NodePort<ContiguousArray<Int>>(name: "Parent Indices", kind: .Outlet, description: "Each piece's parent piece, or -1 for a top-level piece")
    public let outputGenerations = NodePort<ContiguousArray<Float>>(name: "Generations", kind: .Outlet, description: "Each piece's generation: 0 for a top-level piece (such as a piece of the first cut), 1 for a piece cut from one of those, and so on. Whole numbers, as Floats for Math Expression")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputGeometry", port: self.inputGeometry),
            PortDeclaration(key: "outputPieceCount", port: self.outputPieceCount),
            PortDeclaration(key: "outputCenters", port: self.outputCenters),
            PortDeclaration(key: "outputVolumes", port: self.outputVolumes),
            PortDeclaration(key: "outputParentIndices", port: self.outputParentIndices),
            PortDeclaration(key: "outputGenerations", port: self.outputGenerations),
        ]
    }

    private var infoStatuses: [NodeStatus] = []

    override public func deriveStatuses() -> [NodeStatus] { infoStatuses }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.inputGeometry.valueDidChange else { return }
        // A posed view (a Transform Pieces output) reports its rest source's pieces.
        let pieces = self.inputGeometry.value?.skinningSource.pieces

        let statuses: [NodeStatus] = self.inputGeometry.value != nil && pieces == nil
            ? [.warning("Connect geometry with pieces, such as text split into pieces or a cutting node's output; other geometry has none.")]
            : []
        self.infoStatuses = statuses

        self.outputPieceCount.send(pieces?.count ?? 0)
        self.outputCenters.send(ContiguousArray(pieces?.centers ?? []))
        // Pieces measured by area (flat pieces) enclose no volume.
        let volumes = pieces.map { $0.sizeMeasure == .volume ? $0.sizes : Array(repeating: 0, count: $0.count) } ?? []
        self.outputVolumes.send(ContiguousArray(volumes))
        self.outputParentIndices.send(ContiguousArray(pieces?.parentIndices ?? []))
        self.outputGenerations.send(ContiguousArray((pieces?.generations ?? []).map(Float.init)))
    }
}
