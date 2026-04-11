//
//  ImageParameterNode.swift
//  Fabric
//
//  Created by Claude on 4/11/26.
//

import Foundation
import Satin
import Metal

/// Patching utility node for Image ports. Passes through image without modification.
/// Does not have editable inputs.
public class ImageParameterNode: Node
{
    override public class var name: String { "Image" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for Image. Does not have editable inputs." }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet, description: "Input image")),
            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Output image")),
        ]
    }

    // Port Proxy
    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        self.outputImage.send(self.inputImage.value)
    }
}
