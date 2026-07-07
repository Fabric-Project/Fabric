//
//  ArrayMathExpressionNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
internal import MathParser

struct ArrayMathExpressionView: View
{
    @Bindable var model: MathExpressionBaseNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("Writes a math expression evaluated once per output element. Special bindings: i (index), n (count), t (progress 0 to 1). Any other variable becomes a Float array input port; shorter arrays pad with their last element. \n\n [Swift-Math-Expression Documentation](https://github.com/bradhowes/swift-math-parser).")

            Spacer()

            TextField("Array Math Expression", text: $model.stringExpression)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

public class ArrayMathExpressionNode: MathExpressionBaseNode
{
    override public static var name: String { "Array Math Expression" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeDescription: String { "Evaluates a math expression once per output element. Output length matches the longest variable-input array (pad with last element); defaults to 1 when no arrays are connected. Special bindings: i (index), n (count), t (progress 0..1). Other identifiers become Float array input ports." }

    override public class var defaultExpression: String { "dist * sin(t * 2 * pi)" }
    override public class var specialBindings: Set<String> { ["i", "n", "t"] }

    private var forceReeval: Bool = true

    /// A new expression must re-emit even if no input array changed.
    override public func expressionDidReparse() { self.forceReeval = true }

    override public func makeVariablePort(named name: String) -> Port
    {
        NodePort<ContiguousArray<Float>>(
            name: name,
            kind: .Inlet,
            description: "Values for variable '\(name)' — one per output element; shorter arrays pad with last element"
        )
    }

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("outputArray", NodePort<ContiguousArray<Float>>(name: "Array", kind: .Outlet, description: "Array of per-element expression results")),
        ]
    }

    public var outputArray: NodePort<ContiguousArray<Float>> { port(named: "outputArray") }

    override public func settingsView() -> AnyView { AnyView(ArrayMathExpressionView(model: _settingsModel)) }

    // MARK: - Execution

    public override func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let anyChanged = self.inputPorts().contains(where: { $0.valueDidChange })
        guard anyChanged || self.forceReeval else { return }
        guard let evaluator = self.mathEvaluator else { return }
        self.forceReeval = false

        // Don't emit until every variable-input port has propagated at
        // least once. A nil port value means the upstream node hasn't sent
        // yet, and the expression's output is meaningless until it has —
        // substituting zeros would silently emit garbage on the first
        // frames. Matches the scalar Math Expression node's guard.
        let variablePortNames = self.inputPorts().map { $0.name }

        var sourceArrays: [String: ContiguousArray<Float>] = [:]
        for name in variablePortNames
        {
            guard let typedPort: NodePort<ContiguousArray<Float>> = self.findPort(named: name),
                  let source = typedPort.value
            else { return }

            sourceArrays[name] = source
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

        let nAsDouble = Double(count)
        let tDivisor = Float(max(1, count - 1))

        // Below this element count the GCD thread-pool overhead (≈ a few µs
        // of queue/wakeup cost per worker) exceeds the savings from parallel
        // evaluation. Expression eval is heavier than plain arithmetic (one
        // closure call + switch dispatch per element), so the crossover is
        // lower than for simple component operations — empirically ≈ 256-512.
        let concurrentThreshold = 512

        // Evaluator is a struct with only `let` stored properties and Token is
        // an immutable enum, so concurrent calls to eval() with independent
        // variable closures are safe. Each iteration writes a unique index into
        // a pre-sized buffer, so no CoW or append-lock is needed.
        var output = ContiguousArray<Float>(repeating: 0, count: count)

        let evalElement = { (i: Int) in
            let iAsDouble = Double(i)
            let tAsDouble = Double(Float(i) / tDivisor)
            let result = evaluator.eval(variables: { variable in
                switch variable
                {
                case "i": return iAsDouble
                case "n": return nAsDouble
                case "t": return tAsDouble
                default: return Double(variableArrays[variable]?[i] ?? 0)
                }
            })
            // Per-element scrub for legitimate math NaN/Inf (0/0, log(-1),
            // asin out of range, etc) so a single bad element doesn't poison
            // any downstream FloatParameters via the NaN != NaN publisher
            // cycle.
            let f = Float(result)
            output[i] = f.isFinite ? f : 0
        }

        if count >= concurrentThreshold
        {
            DispatchQueue.concurrentPerform(iterations: count) { evalElement($0) }
        }
        else
        {
            for i in 0..<count { evalElement(i) }
        }

        self.outputArray.send(output)
    }
}
