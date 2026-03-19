//
//  StringComparisonNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class StringComparisonNode: Node {
    override public class var name: String { "String Comparison" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Compare two String values" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputStringA", ParameterPort(parameter: StringParameter("String A", "", .inputfield, "First string to compare"))),
            ("inputStringB", ParameterPort(parameter: StringParameter("String B", "", .inputfield, "Second string to compare"))),
            ("inputOperator", ParameterPort(parameter: StringParameter("Operator", "Equals", StringComparisonOperator.allCases.map(\.rawValue), .dropdown, "Comparison operation to perform"))),
            ("outputResult", NodePort<Bool>(name: "Result", kind: .Outlet, description: "Result of the string comparison")),
        ]
    }

    // Port proxies
    public var inputStringA: ParameterPort<String> { port(named: "inputStringA") }
    public var inputStringB: ParameterPort<String> { port(named: "inputStringB") }
    public var inputOperator: ParameterPort<String> { port(named: "inputOperator") }
    public var outputResult: NodePort<Bool> { port(named: "outputResult") }

    private var op = StringComparisonOperator.Equals

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        if inputOperator.valueDidChange,
           let param = inputOperator.value,
           let newOp = StringComparisonOperator(rawValue: param) {
            op = newOp
        }

        if inputOperator.valueDidChange
            || inputStringA.valueDidChange
            || inputStringB.valueDidChange,
           let a = inputStringA.value,
           let b = inputStringB.value {
            outputResult.send(op.perform(lhs: a, rhs: b))
        }
    }
}

// MARK: - Operators

enum StringComparisonOperator: String, CaseIterable {
    case Equals = "Equals"
    case NotEquals = "Not Equals"
    case Contains = "Contains"
    case HasPrefix = "Has Prefix"
    case HasSuffix = "Has Suffix"
    case EqualsIgnoringCase = "Equals (Ignore Case)"
    case ContainsIgnoringCase = "Contains (Ignore Case)"

    func perform(lhs: String, rhs: String) -> Bool {
        switch self {
        case .Equals:               return lhs == rhs
        case .NotEquals:            return lhs != rhs
        case .Contains:             return lhs.contains(rhs)
        case .HasPrefix:            return lhs.hasPrefix(rhs)
        case .HasSuffix:            return lhs.hasSuffix(rhs)
        case .EqualsIgnoringCase:   return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        case .ContainsIgnoringCase: return lhs.localizedCaseInsensitiveContains(rhs)
        }
    }
}
