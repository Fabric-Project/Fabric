//
//  NodeProtocol.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Metal
import Satin
import Combine


@Observable public class Node : Codable, Equatable, Identifiable, Hashable
{
    // User interface name
    public class var name:String {  fatalError("Must be implemented") }
    
    // User interface organizing principle
    public class var nodeType:Node.NodeType { fatalError("Must be implemented") }
    
    // Execution mode value is used to determine when this node is evaluated
    public class var nodeExecutionMode: Node.ExecutionMode { fatalError("Must be implemented") }
    
    // User interface description
    public class var nodeDescription: String { fatalError("Must be implemented") }

    // Equatable
    public let id:UUID
    
    // Hashable
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
    
    // Equatable
    public static func == (lhs: Node, rhs: Node) -> Bool
    {
        return lhs.id == rhs.id
    }
    
    public var name : String
    {
        let myType = type(of: self)
        return  myType.name
    }
    
    @ObservationIgnored public var nodeType:NodeType
    {
        return Self.nodeType
    }
    
    @ObservationIgnored public var nodeExecutionMode:ExecutionMode
    {
        return Self.nodeExecutionMode
    }
    
    @ObservationIgnored var context:Context

    @ObservationIgnored weak var graph:Graph?

    @ObservationIgnored public var inputParameters:[any Parameter] { []  }
    @ObservationIgnored public let parameterGroup:ParameterGroup = ParameterGroup("Parameters", [])
    
    @ObservationIgnored private var inputParameterPorts:[Port] = []
    
    public var ports:[Port] { self.inputParameterPorts  }
    public private(set) var inputNodes:[Node] = []
    public private(set) var outputNodes:[Node]  = []
    
    public var isSelected:Bool = false
    public var isDragging:Bool = false
    //    var showParams:Bool = false
    
    public var nodeSize:CGSize { self.computeNodeSize() }
    
    public var offset: CGSize = .zero
    
    // Dirty Handling
    //    @ObservationIgnored var lastEvaluationTime: TimeInterval = -1
    @ObservationIgnored private(set) public var isDirty: Bool = true
    
    // Input Parameter update tracking:
    @ObservationIgnored var inputParamCancellables: [AnyCancellable] = []

    enum CodingKeys : String, CodingKey
    {
        case id
        case nodeOffset
        case ports

        // Deperecated...
        case inputParameters
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.context = decodeContext.documentContext
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: .id)
        self.offset = try container.decode(CGSize.self, forKey: .nodeOffset)
  
        // get a single value container
        if let ports = try container.decodeIfPresent([Port].self, forKey: .ports)
        {
            self.inputParameterPorts = ports
        }
        
        
//        self.inputParameterPorts = self.parametersGroupToPorts(self.inputParameters)
        self.parameterGroup.append(self.inputParameters)
        
        for parameter in self.inputParameters
        {
            let cancellable = self.makeCancelable(parameter: parameter)
//
            self.inputParamCancellables.append(cancellable)
        }
        
        for port in self.ports
        {
            port.node = self
        }
    }
    
    public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.id, forKey: .id)
        try container.encode(self.offset, forKey: .nodeOffset)
        
        try container.encode(self.ports, forKey: .ports)
//        try container.encode(self.parameterGroup, forKey: .inputParameters)
    }
    
    public required init (context:Context)
    {
        self.id = UUID()
        self.context = context
        self.inputParameterPorts = self.parametersGroupToPorts(self.inputParameters)
        self.parameterGroup.append(self.inputParameters)
        
        for parameter in self.inputParameters
        {
            let cancellable = self.makeCancelable(parameter: parameter)
//
            self.inputParamCancellables.append(cancellable)
        }
        
        for port in self.ports
        {
            port.node = self
        }
    }
    
    deinit
    {
        print("Deleted node \(id)")
    }
    
    
    
    public func didConnectToNode(_ node: Node)
    {
        self.inputNodes = calcInputNodes()
        self.outputNodes = calcOutputNodes()
    }
    
    public func didDisconnectFromNode(_ node: Node)
    {
        self.inputNodes = calcInputNodes()
        self.outputNodes = calcOutputNodes()
    }

    private func calcInputNodes() -> [Node]
    {
        let nodeInputs = self.ports.filter( { $0.kind == .Inlet } )
        let inputNodes = nodeInputs.compactMap { $0.connections.compactMap(\.node) }.flatMap(\.self)
  
        return inputNodes
//        return Array(Set(inputNodes))
    }
    
    private func calcOutputNodes() -> [Node]
    {
        let nodeOutputs = self.ports.filter( { $0.kind == .Outlet } )
        let outputNodes = nodeOutputs.compactMap { $0.connections.compactMap(\.node) }.flatMap(\.self)
  
        return outputNodes
//        return Array(Set(outputNodes))
    }
    
    public func publishedPorts() -> [Port]
    {
        return self.ports.filter( { $0.published } )
    }
    
    public func publishedParameterPorts() -> [Port]
    {
        return self.inputParameterPorts.filter( { $0.published } )
    }
    
    public func markClean()
    {
        isDirty = false
        
        // See https://github.com/Fabric-Project/Fabric/issues/41
        for port in ports
        {
            port.valueDidChange = false
        }
    }
    
    public func markDirty()
    {
        isDirty = true
        
        // Might not strictly be necrssary?
        // self.outputNodes().forEach( { $0.markDirty() } )
    }
    
    private func makeCancelable(parameter: some Parameter) -> AnyCancellable
    {
        let cancellable = parameter.valuePublisher.eraseToAnyPublisher().sink{ [weak self] _ in
            self?.markDirty()
        }
        
        return cancellable
    }
    
    public func startExecution(context:GraphExecutionContext) { }
    public func stopExecution(context:GraphExecutionContext) { }

    public func enableExecution(context:GraphExecutionContext) { }
    public func disableExecution(context:GraphExecutionContext) { }
    
    public func execute(context:GraphExecutionContext,
                         renderPassDescriptor: MTLRenderPassDescriptor,
                         commandBuffer: MTLCommandBuffer) { }
    
    public func resize(size: (width: Float, height: Float), scaleFactor: Float) { }
   
    func computeNodeSize() -> CGSize
    {
        let horizontalInputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Inlet  }.count
        let horizontalOutputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Outlet  }.count

        let verticalInputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Inlet  }.count
        let verticalOutputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Outlet  }.count

        let horizontalMax = max(horizontalInputsCount, horizontalOutputsCount)
        let verticalMax = max(verticalInputsCount, verticalOutputsCount)
        
        let height:CGFloat = 40 + (CGFloat(horizontalMax) * 25)
        let width:CGFloat = 20 + (CGFloat(verticalMax) * 25)
        
        return CGSize(width: max(width, 150), height: max(height, 60) )
    }
    
    // Mark - Private helper
    
    private func parametersGroupToPorts(_ parameters:[(any Parameter)]) -> [Port]
    {
//        print(self.name, "parametersGroupToPorts")
        return parameters.compactMap( {
            self.parameterToPort(parameter:$0) })
    }
    
    private func parameterToPort(parameter:(any Parameter)) -> Port?
    {
//        print(self.name, "parameterToPort", parameter.label)
                
        switch parameter.type
        {
            
        case .generic:
            
            if let genericParam = parameter as? GenericParameter<Float>
            {
                return ParameterPort(parameter: genericParam)
            }
            
            if let genericParam = parameter as? GenericParameter<simd_float3>
            {
                return ParameterPort(parameter: genericParam)
            }
            
            if let genericParam = parameter as? GenericParameter<simd_float4>
            {
                return ParameterPort(parameter: genericParam)
            }
            
            if let genericParam = parameter as? GenericParameter<simd_quatf>
            {
                return ParameterPort(parameter: genericParam)
            }
            
        case .string:
            
            if let genericParam = parameter as? StringParameter
            {
                return ParameterPort(parameter: genericParam)
            }

        case .bool:

            if let genericParam = parameter as? BoolParameter
            {
                return ParameterPort(parameter: genericParam)
            }
            
        case .float:
            
            if let genericParam = parameter as? FloatParameter
            {
                return ParameterPort(parameter: genericParam)
            }

            else if let genericParam = parameter as? GenericParameter<Float>
            {
                return ParameterPort(parameter: genericParam)
            }

        case .float2:
            if let genericParam = parameter as? Float2Parameter
            {
                return ParameterPort(parameter: genericParam)
            }
            
        case .float3:
            if let genericParam = parameter as? Float3Parameter
            {
                return ParameterPort(parameter: genericParam)
            }
            
        case .float4:
            if let genericParam = parameter as? Float4Parameter
            {
                return ParameterPort(parameter: genericParam)
            }
            
            else if let genericParam = parameter as? GenericParameter<simd_float4>
            {
                return ParameterPort(parameter: genericParam)
            }
            
        case .float2x2:
            if let genericParam = parameter as? Float2x2Parameter
            {
                return ParameterPort(parameter: genericParam)
            }
            
        case .float3x3:
            if let genericParam = parameter as? Float3x3Parameter
            {
                return ParameterPort(parameter: genericParam)
            }

        case .float4x4:
            if let genericParam = parameter as? Float4x4Parameter
            {
                return ParameterPort(parameter: genericParam)
            }

        default:
            return nil

        }
        
        return nil
    }
}

protocol NodeFileLoadingProtocol : Node
{
    init(context:Context, fileURL:URL) throws
}
