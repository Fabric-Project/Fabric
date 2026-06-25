//
//  ArrayMathGeneratorNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
internal import MathParser

/// Generates an array by evaluating a math expression once per element. Each
/// free variable is a single constant Float value applied to every element, combined
/// with the built-in bindings i (index), n (count) and t (position 0…1). A
/// Count input determines how many elements are produced.
public class ArrayMathGeneratorNode: ArrayMathExpressionBaseNode
{
    override public static var name: String { "Array Math Generator" }
    override public class var nodeDescription: String { "Use a mathematical expression to generate a numerical array based on count and any constant inputs. Built-in bindings i (index), n (count) and t (position 0 to 1) are available per element." }

    override public class var defaultExpression: String { "step * i" }

    /// Display name of the element-count input port.
    private static let countPortName = "Count"

    /// Default and upper bound for the generated element count. The cap stops a
    /// large typed value from allocating/evaluating an unbounded array.
    private static let defaultCount = 16
    private static let maxCount = 4096

    /// The Count input is a declared port, not a free variable, so exclude it
    /// from the expression's variable-port sync.
    override public var reservedVariablePortNames: Set<String> { [Self.countPortName] }

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        // Declared first so the Count input always sorts ahead of the dynamic
        // variable ports the expression creates.
        return [
            (countPortName, ParameterPort(parameter: IntParameter(countPortName, defaultCount, 1, maxCount, .inputfield, "Number of values to generate (max \(maxCount))"))),
        ] + super.registerPorts(context: context)
    }

    private var countPort: ParameterPort<Int>? { self.findPort(named: Self.countPortName, as: ParameterPort<Int>.self) }

    override public func makeVariablePort(named name: String) -> Port
    {
        ParameterPort(parameter: FloatParameter(name, 0.0, .inputfield))
    }

    // MARK: - Execution

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let evaluator = self.mathEvaluator else { return }

        let ports = self.inputPorts()
        guard self.shouldReevaluate(inputPorts: ports) else { return }

        // Count comes from the Count input, clamped to the supported maximum so
        // a huge typed value can't allocate/iterate an unbounded array.
        let rawCount = self.countPort?.value ?? Self.defaultCount
        let count = min(Self.maxCount, max(1, rawCount))

        // Each variable is a single constant value applied to every element. A missing
        // value contributes 0 rather than aborting, so the generator keeps
        // emitting regardless of what is (or isn't) connected.
        var variableValues: [String: Float] = [:]
        for port in ports where port.name != Self.countPortName
        {
            variableValues[port.name] = (port as? NodePort<Float>)?.value ?? 0
        }

        let output = self.evaluate(evaluator, count: count) { variable, _ in
            Double(variableValues[variable] ?? 0)
        }

        self.outputArray.send(output)
    }
}
