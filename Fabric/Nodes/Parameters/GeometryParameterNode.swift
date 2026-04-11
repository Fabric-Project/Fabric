//
//  GeometryParameterNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import Metal

/// Patching utility node for Geometry ports. Passes through geometry without modification.
/// Does not have editable inputs.
public class GeometryParameterNode: Node
{
    override public class var name: String { "Geometry" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for Geometry. Does not have editable inputs." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputGeometry", NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet, description: "Input geometry")),
            ("outputGeometry", NodePort<SatinGeometry>(name: "Geometry", kind: .Outlet, description: "Output geometry")),
        ]
    }

    // Port Proxy
    public var inputGeometry: NodePort<SatinGeometry> { port(named: "inputGeometry") }
    public var outputGeometry: NodePort<SatinGeometry> { port(named: "outputGeometry") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputGeometry.send(self.inputGeometry.value)
    }
}
