//
//  CurrentDateNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class CurrentDateNode: Node {
    override public class var name: String { "Current Date" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide the current Date and Time" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("outputDate", NodePort<Date>(name: "Date", kind: .Outlet, description: "Current date and time")),
            ("outputString", NodePort<String>(name: "String", kind: .Outlet, description: "Current date and time as a formatted string")),
        ]
    }

    // Port proxies
    public var outputDate: NodePort<Date> { port(named: "outputDate") }
    public var outputString: NodePort<String> { port(named: "outputString") }

    private let formatter = DateFormatter()

    public override func startExecution(context: GraphExecutionContext) {
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        let now = Date()
        outputDate.send(now)
        outputString.send(formatter.string(from: now))
    }
}
