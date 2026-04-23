//
//  MakeTransformsArrayFromRectsNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class MakeTransformsArrayFromRectsNode : Node
{
    override public class var name: String { "Make Transforms Array From Rects" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Transform) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Turns an array of rects into an array of 4x4 model transforms. Each transform places a centered unit quad (-0.5..0.5 in local XY) at the rect in the world XY plane (Z = 0): T(rect.x + rect.w/2, rect.y + rect.h/2, 0) * S(rect.w, rect.h, 1). Useful paired with Transform2D Array From Rects to drive the Transforms and UV Transform2Ds inputs of UV Instanced Mesh from the same rect arrays." }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputRects", NodePort<ContiguousArray<simd_float4>>(name: "Rects", kind: .Inlet, description: "Per-element rect (x, y, width, height) in the XY plane")),
            ("outputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Outlet, description: "Array of 4x4 model transforms, one per input rect")),
        ]
    }

    public var inputRects: NodePort<ContiguousArray<simd_float4>> { port(named: "inputRects") }
    public var outputTransforms: NodePort<ContiguousArray<simd_float4x4>> { port(named: "outputTransforms") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputRects.valueDidChange else { return }
        guard let rects = self.inputRects.value else { return }

        var output = ContiguousArray<simd_float4x4>()
        output.reserveCapacity(rects.count)
        for rect in rects {
            let w = rect.z
            let h = rect.w
            let cx = rect.x + w * 0.5
            let cy = rect.y + h * 0.5
            // T(cx, cy, 0) * S(w, h, 1), column-major.
            output.append(simd_float4x4(
                simd_float4(w, 0, 0, 0),
                simd_float4(0, h, 0, 0),
                simd_float4(0, 0, 1, 0),
                simd_float4(cx, cy, 0, 1)
            ))
        }
        self.outputTransforms.send(output)
    }
}
