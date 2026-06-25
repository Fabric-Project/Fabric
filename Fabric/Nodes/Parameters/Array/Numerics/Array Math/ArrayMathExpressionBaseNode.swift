//
//  ArrayMathExpressionBaseNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
internal import MathParser

/// Settings panel shared by the array math-expression nodes: a description and
/// the editable expression field. The wording is supplied per node.
struct ArrayMathExpressionSettingsView: View
{
    @Bindable var model: MathExpressionBaseNode.SettingsModel
    let helpText: String

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("\(helpText)\n\n [Swift-Math-Expression Documentation](https://github.com/bradhowes/swift-math-parser).")

            Spacer()

            TextField("Expression", text: $model.stringExpression)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

/// Shared base for the array math-expression nodes. Both evaluate a user
/// expression once per output element, exposing `i` (index), `n` (count) and
/// `t` (progress / position 0…1) as built-in bindings and every other
/// identifier as an input port. Subclasses decide the port value type and
/// where the element count comes from:
///
/// - ``ArrayMathProcessorNode`` — variables are Float arrays; the output length
///   follows the longest input.
/// - ``ArrayMathGeneratorNode`` — variables are single constant values; a Count
///   input sets the output length.
public class ArrayMathExpressionBaseNode: MathExpressionBaseNode
{
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var specialBindings: Set<String> { ["i", "n", "t"] }

    /// Description shown in the settings panel. Defaults to the node's browser
    /// description so the two don't drift apart.
    public class var helpText: String { nodeDescription }

    /// A re-parse (or a freshly created node) must emit once even if no input
    /// port reported a change this frame.
    var forceReeval: Bool = true
    override public func expressionDidReparse() { self.forceReeval = true }

    public required init(context: Context)
    {
        super.init(context: context)
        // The base leaves a freshly created node unevaluated, so its default
        // expression's variable ports wouldn't exist until the first edit.
        // Evaluate now so those input ports appear on creation.
        self.reevaluateExpression()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
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

    override public func settingsView() -> AnyView { AnyView(ArrayMathExpressionSettingsView(model: _settingsModel, helpText: Self.helpText)) }

    // MARK: - Execution helpers

    /// Whether the node should re-emit this frame — true if any input changed
    /// or a re-parse forced it — clearing the force flag as a side effect.
    /// Takes the already-fetched input ports so `execute` scans them only once.
    func shouldReevaluate(inputPorts ports: [Port]) -> Bool
    {
        let anyChanged = ports.contains(where: { $0.valueDidChange })
        guard anyChanged || self.forceReeval else { return false }
        self.forceReeval = false
        return true
    }

    /// Per-element evaluation loop shared by both nodes. Resolves the built-in
    /// bindings i/n/t and delegates every other identifier to `resolve`, which
    /// is given the variable name and the current element index.
    func evaluate(_ evaluator: Evaluator,
                  count: Int,
                  resolve: @escaping (_ variable: String, _ i: Int) -> Double) -> ContiguousArray<Float>
    {
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
                default: return resolve(variable, i)
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

        return output
    }
}
