//
//  GridPointsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class GridPointsNode : Node
{
    public override class var name: String { "Grid Points" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Generates cols x rows points on a grid, centred on the origin, in row-major order (row 0 first). The Orientation quaternion rotates a canonical local frame (columns along local +X, rows along local +Y, normal +Z) into world space. Identity orientation places the grid in the XY plane." }

    public let inputColumns = ParameterPort(parameter: IntParameter("Columns", 4, 0, 1024, .inputfield, "Number of columns"))
    public let inputRows = ParameterPort(parameter: IntParameter("Rows", 4, 0, 1024, .inputfield, "Number of rows"))
    public let inputColumnSpacing = ParameterPort(parameter: FloatParameter("Column Spacing", 1.0, 0.0, 1000.0, .inputfield, "Distance between adjacent columns"))
    public let inputRowSpacing = ParameterPort(parameter: FloatParameter("Row Spacing", 1.0, 0.0, 1000.0, .inputfield, "Distance between adjacent rows"))
    public let inputOrientation = ParameterPort(parameter: Float4Parameter("Up Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion rotating the canonical frame (+X=cols, +Y=rows, +Z=normal) into world space. Same format as the Look At node's Up Orientation, so one source can drive both."))
    public let outputPositions = NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Outlet, description: "Array of cols*rows per-point world-space positions, row-major")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputColumns", port: self.inputColumns),
            PortDeclaration(key: "inputRows", port: self.inputRows),
            PortDeclaration(key: "inputColumnSpacing", port: self.inputColumnSpacing),
            PortDeclaration(key: "inputRowSpacing", port: self.inputRowSpacing),
            PortDeclaration(key: "inputOrientation", port: self.inputOrientation),
            PortDeclaration(key: "outputPositions", port: self.outputPositions),
        ]
    }

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.inputColumns.valueDidChange
            || self.inputRows.valueDidChange
            || self.inputColumnSpacing.valueDidChange
            || self.inputRowSpacing.valueDidChange
            || self.inputOrientation.valueDidChange
        else { return }

        let cols = max(0, self.inputColumns.value ?? 0)
        let rows = max(0, self.inputRows.value ?? 0)
        let count = cols * rows
        guard count > 0 else {
            self.outputPositions.send(ContiguousArray<simd_float3>())
            return
        }

        let colSpacing = max(0.0, self.inputColumnSpacing.value ?? 1.0)
        let rowSpacing = max(0.0, self.inputRowSpacing.value ?? 1.0)
        let orientation = simd_quatf(vector: self.inputOrientation.value ?? simd_float4(0, 0, 0, 1)).normalized

        // The orientation is constant across all points, so resolve the grid's
        // local X/Y axes into world space once; each point is x * xAxis plus a
        // per-row y term hoisted out of the inner loop.
        let basis = matrix_float3x3(orientation)
        let xAxis = basis.columns.0
        let yAxis = basis.columns.1

        let xOrigin = -Float(cols - 1) * 0.5 * colSpacing
        let yOrigin = -Float(rows - 1) * 0.5 * rowSpacing

        var output = ContiguousArray<simd_float3>()
        output.reserveCapacity(count)
        for r in 0..<rows {
            let yTerm = (yOrigin + Float(r) * rowSpacing) * yAxis
            for c in 0..<cols {
                let x = xOrigin + Float(c) * colSpacing
                output.append(x * xAxis + yTerm)
            }
        }
        self.outputPositions.send(output)
    }
}
