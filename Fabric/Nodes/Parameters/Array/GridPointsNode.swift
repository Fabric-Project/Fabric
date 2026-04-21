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

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputColumns", ParameterPort(parameter: IntParameter("Columns", 4, 0, 1024, .inputfield, "Number of columns"))),
            ("inputRows", ParameterPort(parameter: IntParameter("Rows", 4, 0, 1024, .inputfield, "Number of rows"))),
            ("inputColumnSpacing", ParameterPort(parameter: FloatParameter("Column Spacing", 1.0, 0.0, 1000.0, .inputfield, "Distance between adjacent columns"))),
            ("inputRowSpacing", ParameterPort(parameter: FloatParameter("Row Spacing", 1.0, 0.0, 1000.0, .inputfield, "Distance between adjacent rows"))),
            ("inputOrientation", ParameterPort(parameter: Float4Parameter("Orientation", simd_float4(0, 0, 0, 1), .inputfield, "Quaternion rotating the canonical frame (+X=cols, +Y=rows, +Z=normal) into world space"))),
            ("outputPositions", NodePort<ContiguousArray<simd_float3>>(name: "Positions", kind: .Outlet, description: "Array of cols*rows per-point world-space positions, row-major")),
        ]
    }

    public var inputColumns: ParameterPort<Int> { port(named: "inputColumns") }
    public var inputRows: ParameterPort<Int> { port(named: "inputRows") }
    public var inputColumnSpacing: ParameterPort<Float> { port(named: "inputColumnSpacing") }
    public var inputRowSpacing: ParameterPort<Float> { port(named: "inputRowSpacing") }
    public var inputOrientation: ParameterPort<simd_float4> { port(named: "inputOrientation") }
    public var outputPositions: NodePort<ContiguousArray<simd_float3>> { port(named: "outputPositions") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
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

        let xOrigin = -Float(cols - 1) * 0.5 * colSpacing
        let yOrigin = -Float(rows - 1) * 0.5 * rowSpacing

        var output = ContiguousArray<simd_float3>()
        output.reserveCapacity(count)
        for r in 0..<rows {
            let y = yOrigin + Float(r) * rowSpacing
            for c in 0..<cols {
                let x = xOrigin + Float(c) * colSpacing
                let local = simd_float3(x, y, 0)
                output.append(orientation.act(local))
            }
        }
        self.outputPositions.send(output)
    }
}
