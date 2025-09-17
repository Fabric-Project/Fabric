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

class StringRangeNode : Node, NodeProtocol
{
    static let name = "String Range"
    static var nodeType = Node.NodeType.Parameter(parameterType: .String)

    let inputRangeTo:FloatParameter
    override var inputParameters: [any Parameter] { [self.inputRangeTo] + super.inputParameters}

    let inputPort:NodePort<String>
    let outputPort:NodePort<String>
    override var ports: [any NodePortProtocol] {  [inputPort, outputPort] + super.ports}

    private var url: URL? = nil
    private var string: String? = nil
    
    required init(context:Context)
    {
        self.inputPort = NodePort<String>(name: "String", kind: .Inlet)
        self.inputRangeTo = FloatParameter("To", 0, .inputfield)
        self.outputPort = NodePort<String>(name: "String", kind: .Outlet)
        
        super.init(context: context)
        
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputPort
        case inputRangeToParameter
        case outputPort
    }
    
    override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputPort, forKey: .inputPort)
        try container.encode(self.inputRangeTo, forKey: .inputRangeToParameter)
        try container.encode(self.outputPort, forKey: .outputPort)

        try super.encode(to: encoder)
    }
    
    required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
       
        self.inputPort = try container.decode(NodePort<String>.self, forKey: .inputPort)
        self.inputRangeTo = try container.decode(FloatParameter.self, forKey: .inputRangeToParameter)
        self.outputPort = try container.decode(NodePort<String>.self, forKey: .outputPort)
        
        try super.init(from:decoder)
    }
    
    override func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputPort.valueDidChange || self.inputRangeTo.valueDidChange
        {
            if let string = self.inputPort.value
            {
                let offset = max(0, Int(self.inputRangeTo.value) )
                let endIndex = string.index(string.startIndex, offsetBy:offset, limitedBy: string.endIndex)
                
                let substring = string[ string.startIndex ..< (endIndex ?? string.endIndex) ]
                
                self.outputPort.send( String(substring) )
            }
            else
            {
                self.outputPort.send( nil )
            }
        }
    }
}
