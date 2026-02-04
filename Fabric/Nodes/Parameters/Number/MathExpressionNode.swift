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
    
    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("By writing a mathematical expression, you can expose variables and use built in functions or constants to compute a single output value. \n\n [Swift-Math-Expression Documentation](https://github.com/bradhowes/swift-math-parser).")
            
            Spacer()
            
            TextField("Math Expression", text: $node.stringExpression)
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

@Observable public class MathExpressionNode : Node
{
    override public static var name:String { "Math Expression" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide math function with variables and get a single numerical result"}

    override public var name: String { stringExpression }

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

    // MARK: - Properties

    @ObservationIgnored fileprivate var stringExpression:String = "sin(x) + y^2"
    {
        didSet
        {
            self.evalExpression()
        }
    }

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
            print("executing math expression")
            let result = mathEvaluator.eval(variables: { variable in
                                
                if let port = self.findPort(named: variable) as? NodePort<Float>,
                   let portValue = port.value
                {
                    return Double(portValue)
                }
                
                return Double.nan
            })
            
            self.outputNumber.send( Float(result) )
        }
    }
    
    private func evalExpression()
    {
        let evaluator = mathParser.parseResult(self.stringExpression)
        
        switch evaluator
        {
        case .success(let evaluator):
            self.mathEvaluator = evaluator
            self.registerPorts(forEvaluator: evaluator)
            
        case .failure:
            self.mathEvaluator = nil
            
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
