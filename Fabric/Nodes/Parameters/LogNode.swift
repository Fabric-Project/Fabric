//
//  LogNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/10/25.
//


import Foundation
import Satin
import simd
import Metal

public class AnyLoggable: Equatable, CustomDebugStringConvertible
{
    private let _isEqual: (AnyLoggable) -> Bool
    private let _debugDescription: () -> String
    private var storage: Any?
    
    public init<T: Equatable & CustomDebugStringConvertible>(_ value: T)
    {
        self.storage = value
        
        self._isEqual = { other in
            guard let rhs = other.storage as? T else { return false } // different types → not equal
            return value == rhs
        }
        
        self._debugDescription = { value.debugDescription }
    }

    public static func == (lhs: AnyLoggable, rhs: AnyLoggable) -> Bool
    {
        lhs._isEqual(rhs)
    }

    public var debugDescription: String {
        _debugDescription()
    }

    // Optional: a typed accessor
    public func asType<T>(_ type: T.Type) -> T? { storage as? T }
    public func setAsType<T>(_ type: T.Type, value: T?) {
        storage = value
    }
}


public class LogNode : Node
{
    override public class var name:String { "Log" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Utility }

    // Ports
    public let inputAny: NodePort<AnyLoggable>
    public override var ports: [any NodePortProtocol] {  [self.inputAny] + super.ports }
    
    public required init(context: Context)
    {
        self.inputAny = NodePort<AnyLoggable>(name: "Log Value" , kind: .Inlet)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputAnyPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputAny, forKey: .inputAnyPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputAny = try container.decode(NodePort<AnyLoggable>.self, forKey: .inputAnyPort)
        
        try super.init(from: decoder)
    }
            
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        print("Log Executing")
        if self.inputAny.valueDidChange
        {
            print(self.inputAny.value?.debugDescription ?? "Nil")
        }
    }
}
