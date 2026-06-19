//
//  TimecodeFormatterNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class TimecodeFormatterNode: Node {
    override public class var name: String { "Timecode Formatter" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Convert a time value in seconds to a timecode formatted String" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputTime", ParameterPort(parameter: FloatParameter("Seconds", 0.0, .inputfield, "Time value in seconds"))),
            ("inputFPS", ParameterPort(parameter: IntParameter("FPS", 30, .inputfield, "Frames per second for frame count"))),
            ("outputPort", NodePort<String>(name: "Timecode", kind: .Outlet, description: "Formatted timecode string (HH:MM:SS:FF)")),
        ]
    }

    // Port proxies
    public var inputTime: ParameterPort<Float> { port(named: "inputTime") }
    public var inputFPS: ParameterPort<Int> { port(named: "inputFPS") }
    public var outputPort: NodePort<String> { port(named: "outputPort") }

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        if inputTime.valueDidChange || inputFPS.valueDidChange,
           let time = inputTime.value,
           let fps = inputFPS.value,
           fps > 0 {
            let totalSeconds = max(0, time)
            let hours = Int(totalSeconds) / 3600
            let minutes = (Int(totalSeconds) % 3600) / 60
            let seconds = Int(totalSeconds) % 60
            let frames = Int((totalSeconds - Float(Int(totalSeconds))) * Float(fps))

            outputPort.send(String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames))
        }
    }
}
