//
//  ArrayRangeEasingNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

public class ArrayRangeInterpolationNode<Value: PortValueRepresentable & Lerpable & ParameterValueType>: Node
{
    public override class var name: String { "\(Value.portType.rawValue) Array Range Interpolation" }
    public override class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Generates a \(Value.portType.rawValue) array of Count elements interpolated from From to To using the selected easing function." }

    public let inputFrom = NodePort<Value>.makeFresh(name: "From", kind: .Inlet, description: "Start value of the interpolation range")
    public let inputTo = NodePort<Value>.makeFresh(name: "To", kind: .Inlet, description: "End value of the interpolation range")
    public let inputCount = ParameterPort(parameter: IntParameter("Count", 6, 0, 1024, .inputfield, "Number of elements to generate"))
    public let inputEasing = ParameterPort(parameter: StringParameter("Easing", "Linear", TweenEasing.titles, .dropdown, "Easing function applied to the interpolation"))
    public let outputArray = NodePort<ContiguousArray<Value>>(name: "Array", kind: .Outlet, description: "Array of eased \(Value.portType.rawValue) values from From to To")

    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + [
            PortDeclaration(key: "inputFrom", port: self.inputFrom),
            PortDeclaration(key: "inputTo", port: self.inputTo),
            PortDeclaration(key: "inputCount", port: self.inputCount),
            PortDeclaration(key: "inputEasing", port: self.inputEasing),
            PortDeclaration(key: "outputArray", port: self.outputArray),
        ]
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        guard self.inputFrom.valueDidChange
           || self.inputTo.valueDidChange
           || self.inputCount.valueDidChange
           || self.inputEasing.valueDidChange
        else { return }

        guard let from   = self.inputFrom.value,
              let to     = self.inputTo.value,
              let count  = self.inputCount.value,
              let easingName = self.inputEasing.value,
              let easeFunc   = TweenEasing.map[easingName]
        else { return }

        if count == 0
        {
            self.outputArray.send(ContiguousArray<Value>())
            return
        }

        if count == 1
        {
            self.outputArray.send(ContiguousArray<Value>([from]))
            return
        }

        let divisor = Float(count - 1)
        var output = ContiguousArray<Value>()
        output.reserveCapacity(count)

        for i in 0..<count
        {
            let t = Float(i) / divisor
            let easedT = Float(easeFunc.function(Double(t)))
            output.append(Value.lerp(from, to, easedT))
        }

        self.outputArray.send(output)
    }
}
