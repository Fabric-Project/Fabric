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
    let node:MathExpressionNode
    
    var body: some View
    {
        @Bindable var bindableNode = node

        VStack(alignment: .leading)
        {
            TextField("Math Expression", text: $bindableNode.stringExpression)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
        }
    }
}

public class MathExpressionNode : Node
{
    override public static var name:String { "Math Expression" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Provide math function with variables and get a single numerical result"}
   
    fileprivate var stringExpression:String = "sin(x) + y^2"
    let mathParser = MathParser()
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("outputNumber", NodePort<Float>(name: NumberNode.name , kind: .Outlet)),
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
      
        let evaluator = mathParser.parse(stringExpression)
        
        
        
        print(evaluator?.unresolved.variables ?? "no variables")
    }
}
