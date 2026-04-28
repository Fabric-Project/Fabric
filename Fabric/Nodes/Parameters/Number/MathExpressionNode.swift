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
    @Bindable var node:MathExpressionNode

    /// Local edit buffer between the TextField and the node.
    ///
    /// Why this exists: binding the TextField directly to an
    /// `@Observable` `node.stringExpression` causes the field to
    /// select-all-on-update on every keystroke. Each write
    /// invalidates the body, `@Bindable` synthesises a fresh
    /// `Binding<String>`, and SwiftUI's macOS TextField representable
    /// reads that as an external change — pushing the value back
    /// into the underlying `NSTextField`, whose `stringValue` setter
    /// selects-all by default. With `@State` here, SwiftUI's
    /// value-equality optimisation kicks in (the value the field just
    /// emitted equals the value the binding now reports) and the
    /// AppKit field is left untouched. The cursor / selection
    /// survives the eval.
    @State private var buffer: String = ""
    /// Tracks the in-flight debounce. Cancelled on each keystroke so
    /// only the trailing edit triggers a re-parse + port rebuild.
    @State private var debounceTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    /// How long the field has to stay quiet before the expression
    /// auto-commits. Enter and defocus bypass this and commit
    /// immediately.
    private static let debounceSeconds: Double = 1.0

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("By writing a mathematical expression, you can expose variables and use built in functions or constants to compute a single output value. \n\n [Swift-Math-Expression Documentation](https://github.com/bradhowes/swift-math-parser).")

            Spacer()

            TextField("Math Expression", text: $buffer)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focused)
                .onAppear { buffer = node.stringExpression }
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onChange(of: buffer) { _, _ in
                    // Schedule the eval. Until it fires (or Enter /
                    // defocus pre-empts), the buffer is the source of
                    // truth — the node's `stringExpression` is left
                    // alone so AppKit doesn't see a re-write of the
                    // text and reset selection.
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(for: .seconds(Self.debounceSeconds))
                        guard !Task.isCancelled else { return }
                        commit()
                    }
                }
                .onChange(of: node.stringExpression) { _, new in
                    // External edit (undo / redo / scripted). Sync
                    // the buffer when we're not focused — while the
                    // user is typing, the buffer is authoritative.
                    if !focused, buffer != new {
                        buffer = new
                    }
                }
        }
    }

    private func commit() {
        debounceTask?.cancel()
        let old = node.stringExpression
        let new = buffer
        if new != old {
            registerUndo(from: old, to: new)
            node.stringExpression = new
        }
        node.commitExpression()
    }

    /// Register a single undo step covering this commit's full edit
    /// (every keystroke since the last commit collapses into one
    /// ⌘Z). The symmetric pattern — undo handler registers redo —
    /// bounces back and forth across redo / undo cycles.
    private func registerUndo(from old: String, to new: String) {
        guard let undo = node.graph?.undoManager else { return }
        undo.registerUndo(withTarget: node) { n in
            let redoTarget = n.stringExpression
            n.graph?.undoManager?.registerUndo(withTarget: n) { n2 in
                n2.stringExpression = redoTarget
                n2.commitExpression()
            }
            n.graph?.undoManager?.setActionName("Edit Math Expression")
            n.stringExpression = old
            n.commitExpression()
        }
        undo.setActionName("Edit Math Expression")
    }
}

@Observable public class MathExpressionNode : Node
{
    override public static var name:String { "Math Expression" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide math function with variables and get a single numerical result"}

    override public var name: String { evaluatedDisplayName }

    // MARK: - Codable

    private enum MathExpressionCodingKeys: String, CodingKey
    {
        case stringExpression
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: MathExpressionCodingKeys.self)
        let decodedExpression = try container.decodeIfPresent(String.self, forKey: .stringExpression)

        // Use decoded expression or default
        self.stringExpression = decodedExpression ?? "sin(x) + y^2"

        // Rebuild evaluator and ports based on restored expression
        self.evalExpression()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: MathExpressionCodingKeys.self)
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

    /// Live edit buffer — observable so the inspector's TextField
    /// binding stays in sync with undo/redo + scripted edits, and
    /// the View can `.onChange` it to drive the debounce. Writing to
    /// this property no longer auto-runs the parser; the parse +
    /// port rebuild is gated by `commitExpression()` so it happens
    /// only on the trailing edit (debounce / Enter / defocus).
    public var stringExpression: String = "sin(x) + y^2"

    /// Re-parse the current `stringExpression`, rebuild the variable
    /// ports, and refresh the title. Called by the inspector view
    /// on debounce / Enter / defocus, and by the decoder /
    /// convenience init right after seeding the expression.
    public func commitExpression()
    {
        evalExpression()
    }

    /// Updated by evalExpression() — shows the expression on success, or an
    /// error indicator on parse failure. Observed by SwiftUI via `name`.
    private var evaluatedDisplayName: String = "sin(x) + y^2"

    @ObservationIgnored private let mathParser = MathParser()
    @ObservationIgnored private var mathEvaluator:Evaluator? = nil

    // MARK: - Ports

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet, description: "Result of evaluating the math expression")),
        ]
    }

    // Port Proxy
    public var outputNumber:NodePort<Float> { port(named: "outputNumber") }

    
    
    override public func providesSettingsView() -> Bool {
        true
    }
    
    override public func settingsView() -> AnyView
    {
        AnyView(MathExpressionView(node: self))
    }
    
   
    public override func execute(context:GraphExecutionContext,
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
            // least once, and emitting NaN would otherwise poison downstream
            // FloatParameters via the NaN != NaN publisher cycle. Also scrub
            // legitimate NaN/Inf from the expression itself (0/0, log(-1),
            // asin out of range, etc).
            let output = Float(result)
            guard !sawUnresolvedVariable, output.isFinite else { return }

            self.outputNumber.send( output )
        }
    }
    
    private func evalExpression()
    {
        let evaluator = mathParser.parseResult(self.stringExpression)

        switch evaluator
        {
        case .success(let evaluator):
            self.mathEvaluator = evaluator
            self.evaluatedDisplayName = self.stringExpression
            self.registerPorts(forEvaluator: evaluator)

        case .failure:
            self.mathEvaluator = nil
            self.evaluatedDisplayName = "⚠ \(self.stringExpression)"
        }
    }
    
    private func registerPorts(forEvaluator evaluator:Evaluator)
    {
        let unresolvedVariables = evaluator.unresolved.variables
        
        let unresolvedVariableNames = unresolvedVariables.map( { String($0) } )
        let existingPortNames = self.inputPorts().map { $0.name }
        
        let portsNamesToRemove = Set(existingPortNames).subtracting(Set(unresolvedVariableNames))
        let portNamesToAdd = Set(unresolvedVariableNames).subtracting(portsNamesToRemove)
        
        for portName in portsNamesToRemove
        {
            if let port = self.findPort(named: portName) as? NodePort<Float>
            {
                self.removePort(port)
            }
        }
        
        for portName in portNamesToAdd
        {
            if self.findPort(named: portName) == nil
            {
                let port = ParameterPort(parameter: FloatParameter(portName, 0.0, .inputfield) )
                
                self.addDynamicPort(port, name:portName)
                print("add port \(portName) ")
            }
        }
    }
    
}
