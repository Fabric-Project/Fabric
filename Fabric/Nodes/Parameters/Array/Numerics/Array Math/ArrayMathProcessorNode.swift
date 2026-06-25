//
//  ArrayMathProcessorNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
internal import MathParser

/// Evaluates a math expression once per output element, where each free
/// variable is a Float array input and the output length follows the longest
/// connected input (shorter arrays pad with their last element).
public class ArrayMathProcessorNode: ArrayMathExpressionBaseNode
{
    override public static var name: String { "Array Math Processor" }
    override public class var nodeDescription: String { "Use a mathematical expression to process numeric array input(s) into an output array. The output length follows the longest input; shorter inputs pad with their last element. Built-in bindings i (index), n (count) and t (progress 0 to 1) are available per element." }

    override public class var defaultExpression: String { "(valuesA + valuesB) / 2" }

    override public func makeVariablePort(named name: String) -> Port
    {
        NodePort<ContiguousArray<Float>>(
            name: name,
            kind: .Inlet,
            description: "Values for variable '\(name)' — one per output element; shorter arrays pad with last element"
        )
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

        // Don't emit until every variable-input port has propagated at least
        // once. A nil port value means the upstream node hasn't sent yet, and
        // the expression's output is meaningless until it has — substituting
        // zeros would silently emit garbage on the first frames. Matches the
        // scalar Math Expression node's guard.
        var sourceArrays: [String: ContiguousArray<Float>] = [:]
        for port in ports
        {
            guard let typedPort = port as? NodePort<ContiguousArray<Float>>,
                  let source = typedPort.value
            else { return }

            sourceArrays[port.name] = source
        }

        // Count derives from the longest input array; defaults to 1 when no
        // arrays are connected or all are empty.
        let count = max(1, sourceArrays.values.map(\.count).max() ?? 0)

        // Pad each input to count: shorter arrays repeat their last element,
        // empty arrays become zeros.
        var variableArrays: [String: [Float]] = [:]
        for (name, source) in sourceArrays
        {
            variableArrays[name] = source.paddedToLast(count: count, fallback: 0)
        }

        let output = self.evaluate(evaluator, count: count) { variable, i in
            Double(variableArrays[variable]?[i] ?? 0)
        }

        self.outputArray.send(output)
    }
}
