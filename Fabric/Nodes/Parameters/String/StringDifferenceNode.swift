//
//  StringLengthNode.swift
//  Fabric
//
//  Created by Anton Marini on 9/17/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class StringDifferenceNode : Node
{
    override public static var name:String { "String Difference" }
    override public static var nodeType:Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Find the difference between two strings"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputPort",   ParameterPort(parameter: StringParameter("String", "", .inputfield, "First string to compare"))),
            ("input2Port",  ParameterPort(parameter: StringParameter("String", "", .inputfield, "Second string to compare"))),
            ("outputPort",  NodePort<String>(name: "String", kind: .Outlet, description: "Characters that differ between the two strings")),
        ]
    }
    
    // Port Proxy
    public var inputPort:NodePort<String>   { port(named: "inputPort") }
    public var input2Port:NodePort<String>   { port(named: "input2Port") }
    public var outputPort:NodePort<String>     { port(named: "outputPort") }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.input2Port.valueDidChange
        {

            if let stringA = self.inputPort.value,
                let stringB = self.input2Port.value
            {

                print("String Difference Update")

                let setX = Set(stringA)
                let setY = Set(stringB)
                let diff = setX.union(setY).subtracting( setX.intersection(setY) )
                
                self.outputPort.send( String(diff) )
                
//                let diff = stringA.difference(from: stringB).inferringMoves()
//                let diffArray = diff.map { String.init(describing: $0) }
//                let diffArray:[Character] = diff.compactMap { change in
//                    
//                    switch change
//                    {
//                    case .insert(offset: _, element: let element, associatedWith: _):
//                        return element
//                        
//                    case .remove(offset: _, element: let element, associatedWith: _):
//                        return element
//                    }
//                    
//                }
                
//                self.outputPort.send( diffArray.joined(separator: ", ") )
            }
            else
            {
                print("String Difference got nil values \(String(describing: self.inputPort.value)) \(String(describing: self.input2Port.value))")
            }
//            else
//            {
//                self.outputPort.send( nil )
//            }
        }
    }
}
