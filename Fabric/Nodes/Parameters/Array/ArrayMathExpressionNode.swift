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
    @Bindable var node: ArrayMathExpressionNode

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("Writes a math expression evaluated once per output element. Special bindings: i (index), n (count), t (progress 0 to 1). Any other variable becomes a Float array input port; shorter arrays pad with their last element. \n\n [Swift-Math-Expression Documentation](https://github.com/bradhowes/swift-math-parser).")

            Spacer()

            TextField("Array Math Expression", text: $node.stringExpression)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

@Observable public class ArrayMathExpressionNode: Node
{
    override public static var name: String { "Array Math Expression" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .Array) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Evaluates a math expression once per output element. Output length matches the longest variable-input array (pad with last element); defaults to 1 when no arrays are connected. Special bindings: i (index), n (count), t (progress 0..1). Other identifiers become Float array input ports." }

    override public var name: String { evaluatedDisplayName }

    private static let defaultExpression: String = "dist * sin(t * 2 * pi)"
    private static let specialBindings: Set<String> = ["i", "n", "t"]

    // MARK: - Codable

    private enum ArrayMathExpressionCodingKeys: String, CodingKey
    {
        case stringExpression
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: ArrayMathExpressionCodingKeys.self)
        let decodedExpression = try container.decodeIfPresent(String.self, forKey: .stringExpression)
        self.stringExpression = decodedExpression ?? Self.defaultExpression

        self.evalExpression()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: ArrayMathExpressionCodingKeys.self)
        try container.encode(self.stringExpression, forKey: .stringExpression)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public convenience init(context: Context, expression: String)
    {
        self.init(context: context)
        self.stringExpression = expression
        self.evalExpression()
    }

    // MARK: - Properties

    @ObservationIgnored fileprivate var stringExpression: String = ArrayMathExpressionNode.defaultExpression
    {
        didSet { self.evalExpression() }
    }

    private var evaluatedDisplayName: String = ArrayMathExpressionNode.defaultExpression

    @ObservationIgnored private let mathParser = MathParser()
    @ObservationIgnored private var mathEvaluator: Evaluator? = nil
    @ObservationIgnored private var forceReeval: Bool = true

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("outputArray", NodePort<ContiguousArray<Float>>(name: "Array", kind: .Outlet, description: "Array of per-element expression results")),
        ]
    }

    public var outputArray: NodePort<ContiguousArray<Float>> { port(named: "outputArray") }

    override public func providesSettingsView() -> Bool { true }
    override public func settingsView() -> AnyView { AnyView(ArrayMathExpressionView(node: self)) }

    // MARK: - Expression Parsing

    private func evalExpression()
    {
        let result = mathParser.parseResult(self.stringExpression)

        switch result
        {
        case .success(let evaluator):
            self.mathEvaluator = evaluator
            self.evaluatedDisplayName = self.stringExpression
            self.registerPorts(forEvaluator: evaluator)
            self.forceReeval = true

        case .failure:
            self.mathEvaluator = nil
            self.evaluatedDisplayName = "⚠ \(self.stringExpression)"
        }
    }

    private func registerPorts(forEvaluator evaluator: Evaluator)
    {
        let unresolvedVariables = Set(evaluator.unresolved.variables.map { String($0) })
        let variableNames = unresolvedVariables.subtracting(Self.specialBindings)

        let existingVariablePortNames = Set(self.inputPorts().map { $0.name })

        let portsToRemove = existingVariablePortNames.subtracting(variableNames)
        let portsToAdd = variableNames.subtracting(existingVariablePortNames)

        for portName in portsToRemove
        {
            if let port: Port = findPort(named: portName)
            {
                removePort(port)
            }
        }

        for portName in portsToAdd
        {
            let port = NodePort<ContiguousArray<Float>>(
                name: portName,
                kind: .Inlet,
                description: "Values for variable '\(portName)' — one per output element; shorter arrays pad with last element"
            )
            addDynamicPort(port, name: portName)
        }
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let anyChanged = self.inputPorts().contains(where: { $0.valueDidChange })
        guard anyChanged || self.forceReeval else { return }
        guard let evaluator = self.mathEvaluator else { return }
        self.forceReeval = false

        // Count derives from longest non-empty variable-input array.
        // Defaults to 1 when no arrays are connected or all are empty.
        let variablePortNames = self.inputPorts().map { $0.name }

        var sourceArrays: [String: ContiguousArray<Float>] = [:]
        for name in variablePortNames
        {
            if let typedPort: NodePort<ContiguousArray<Float>> = self.findPort(named: name),
               let source = typedPort.value, !source.isEmpty
            {
                sourceArrays[name] = source
            }
        }

        let count = max(1, sourceArrays.values.map(\.count).max() ?? 0)

        // Pad connected arrays to count; missing variables default to 0.
        var variableArrays: [String: [Float]] = [:]
        for name in variablePortNames
        {
            if let source = sourceArrays[name]
            {
                variableArrays[name] = padLast(source, count: count)
            }
            else
            {
                variableArrays[name] = Array(repeating: 0, count: count)
            }
        }

        let nAsDouble = Double(count)
        let tDivisor = Float(max(1, count - 1))

        var sawUnresolvedVariable = false
        var output = ContiguousArray<Float>()
        output.reserveCapacity(count)
        for i in 0..<count
        {
            let iAsDouble = Double(i)
            let tAsDouble = Double(Float(i) / tDivisor)
            let result = evaluator.eval(variables: { variable in
                switch variable
                {
                case "i": return iAsDouble
                case "n": return nAsDouble
                case "t": return tAsDouble
                default:
                    if let array = variableArrays[variable]
                    {
                        return Double(array[i])
                    }
                    sawUnresolvedVariable = true
                    return 0
                }
            })
            // Per-element scrub for legitimate math NaN/Inf (0/0, log(-1),
            // asin out of range, etc) so a single bad element doesn't poison
            // any downstream FloatParameters via the NaN != NaN publisher
            // cycle.
            let f = Float(result)
            output.append(f.isFinite ? f : 0)
        }

        // Don't emit if any variable was unresolved — the expression's
        // output is meaningless until every input has propagated at
        // least once. Matches the scalar Math Expression node's guard.
        guard !sawUnresolvedVariable else { return }

        self.outputArray.send(output)
    }

    // MARK: - Helpers

    @inline(__always)
    private func padLast(_ array: ContiguousArray<Float>, count: Int) -> [Float]
    {
        if array.isEmpty { return Array(repeating: 0, count: count) }
        if array.count >= count { return Array(array.prefix(count)) }
        return Array(array) + Array(repeating: array.last!, count: count - array.count)
    }
}
