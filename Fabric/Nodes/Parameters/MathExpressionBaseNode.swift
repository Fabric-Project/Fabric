//
//  MathExpressionBaseNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal
import SwiftUI
internal import MathParser

/// Shared base for nodes that parse a user-supplied math expression and
/// expose its free variables as dynamic input ports.
///
/// Subclasses decide the value type of those ports (a scalar `Float` vs a
/// `Float` array), the default expression, any reserved identifiers that are
/// resolved at evaluation time instead of becoming ports, and how the parsed
/// expression is turned into output. Everything else — the editable string,
/// the title shown on parse success/failure, (de)serialization, and keeping
/// the dynamic ports in sync with the expression's variables — lives here.
public class MathExpressionBaseNode: Node
{
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }

    /// Shown as the node's title: the expression on success, or a warning
    /// indicator on parse failure. NodeViewModel caches via nameSubject.
    override public var name: String { evaluatedDisplayName }

    // MARK: - Subclass customization

    /// Expression for a freshly created node, and the fallback when a
    /// document has none stored.
    public class var defaultExpression: String { "" }

    /// Identifiers intercepted during evaluation rather than turned into
    /// input ports (e.g. index/count/progress for the array node).
    public class var specialBindings: Set<String> { [] }

    /// Build the input port for a free variable. Subclasses pick the value
    /// type (e.g. `ParameterPort<Float>` vs `NodePort<ContiguousArray<Float>>`).
    public func makeVariablePort(named name: String) -> Port
    {
        fatalError("\(String(describing: Self.self)) must implement makeVariablePort(named:)")
    }

    /// Called after the expression successfully (re)parses. Default does
    /// nothing; subclasses can use it to force a re-emit.
    public func expressionDidReparse() {}

    /// Input port names the variable-port sync must never add or remove —
    /// subclasses manage these themselves (e.g. a mode-dependent Count input).
    public var reservedVariablePortNames: Set<String> { [] }

    /// Re-parse the current expression and resync ports. For subclasses whose
    /// port construction depends on a setting other than the expression text.
    public func reevaluateExpression() { self.evalExpression() }

    // MARK: - Codable

    private enum MathExpressionCodingKeys: String, CodingKey
    {
        case stringExpression
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: MathExpressionCodingKeys.self)
        let decoded = try container.decodeIfPresent(String.self, forKey: .stringExpression)

        // Initializing assignment — didSet does not fire here, matching the
        // plain-creation path (ports are (re)built by evalExpression below).
        self.stringExpression = decoded ?? Self.defaultExpression

        try super.init(from: decoder)

        // Rebuild evaluator and ports from the restored expression.
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
        // Initializing assignment — didSet does not fire, so a freshly
        // created node does not evaluate until its expression is edited.
        self.stringExpression = Self.defaultExpression
        super.init(context: context)
        self.evaluatedDisplayName = Self.defaultExpression
    }

    public convenience init(context: Context, expression: String)
    {
        self.init(context: context)
        // didSet does not fire for assignments inside an initializer, so parse
        // and register ports explicitly.
        self.stringExpression = expression
        self.evalExpression()
    }

    // MARK: - Properties

    var stringExpression: String
    {
        didSet { self.evalExpression() }
    }

    private var evaluatedDisplayName: String = ""

    private let mathParser = MathParser()
    private(set) var mathEvaluator: Evaluator? = nil

    override public func providesSettingsView() -> Bool { true }

    // MARK: - Settings Model

    @Observable final class SettingsModel
    {
        var stringExpression: String
        {
            didSet
            {
                guard stringExpression != node?.stringExpression else { return }
                node?.stringExpression = stringExpression
            }
        }
        private weak var node: MathExpressionBaseNode?

        init(node: MathExpressionBaseNode)
        {
            self.node = node
            self.stringExpression = node.stringExpression
        }
    }

    internal lazy var _settingsModel: SettingsModel = SettingsModel(node: self)

    // MARK: - Expression parsing

    private func evalExpression()
    {
        switch mathParser.parseResult(self.stringExpression)
        {
        case .success(let evaluator):
            self.mathEvaluator = evaluator
            self.evaluatedDisplayName = self.stringExpression
            self.registerPorts(forEvaluator: evaluator)
            self.expressionDidReparse()

        case .failure:
            self.mathEvaluator = nil
            self.evaluatedDisplayName = "⚠ \(self.stringExpression)"
        }

        self.nameSubject.send()
    }

    /// Sync dynamic input ports to the expression's free variables, leaving
    /// any reserved `specialBindings` to be resolved at evaluation time.
    private func registerPorts(forEvaluator evaluator: Evaluator)
    {
        let reserved = self.reservedVariablePortNames
        let unresolved = Set(evaluator.unresolved.variables.map { String($0) })
        let variableNames = unresolved.subtracting(Self.specialBindings).subtracting(reserved)
        let existingNames = Set(self.inputPorts().map { $0.name }).subtracting(reserved)

        for name in existingNames.subtracting(variableNames)
        {
            if let port: Port = self.findPort(named: name)
            {
                self.removePort(port)
            }
        }

        for name in variableNames.subtracting(existingNames)
        {
            self.addDynamicPort(self.makeVariablePort(named: name), name: name)
        }
    }
}
