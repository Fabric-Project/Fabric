//
//  MathParseNode.swift
//  Fabric
//
//  Created by Anton Marini on 1/19/26.
//

import Foundation
import Satin
import Metal
import SwiftUI
internal import MathParser

struct MathExpressionView : View
{
    @Bindable var model: MathExpressionBaseNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("By writing a mathematical expression, you can expose variables and use built in functions or constants to compute a single output value. \n\n [Swift-Math-Expression Documentation](https://github.com/bradhowes/swift-math-parser).")

            Spacer()

            TextField("Math Expression", text: $model.stringExpression)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

public class MathExpressionNode : MathExpressionBaseNode
{
    override public static var name:String { "Math Expression" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeDescription: String { "Provide math function with variables and get a single numerical result"}

    override public class var defaultExpression: String { "sin(x) + y^2" }

    override public func makeVariablePort(named name: String) -> Port
    {
        ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield))
    }

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("outputNumber", NodePort<Float>(name: "Number" , kind: .Outlet, description: "Result of evaluating the math expression")),
        ]
    }

    // Port Proxy
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }

    override public func settingsView() -> AnyView
    {
        AnyView(MathExpressionView(model: _settingsModel))
    }

    // MARK: - Execution

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let variablePorts = self.inputPorts()

        let anyVariabledChanged = variablePorts.compactMap(\.valueDidChange).contains(true)

        if anyVariabledChanged,
           let mathEvaluator = self.mathEvaluator
        {
            var sawUnresolvedVariable = false
            let result = mathEvaluator.eval(variables: { variable in

                if let port = self.findPort(named: variable) as? NodePort<Float>,
                   let portValue = port.value
                {
                    return Double(portValue)
                }

                sawUnresolvedVariable = true
                return 0
            })

            // Don't emit if any variable was unresolved — the expression's
            // output is meaningless until every input has propagated at
            // least once. Also scrub legitimate NaN/Inf from the expression
            // itself (0/0, log(-1), asin out of range, etc).
            let output = Float(result)
            guard !sawUnresolvedVariable, output.isFinite else { return }

            self.outputNumber.send( output )
        }
    }
}
