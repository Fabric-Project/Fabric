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

public protocol NodeProtocol : AnyObject, Codable, Identifiable
{
    static var name:String { get }
    static var nodeType:Node.NodeType { get }
    
    var id: UUID { get }
    
    var nodeType:Node.NodeType { get }
    var name:String { get }

    init(context:Context)
    
    var ports: [any NodePortProtocol] { get }
    
    var parameterGroup:ParameterGroup { get }
      
    /// Performs the processing or rendering tasks appropriate for the custom patch.
    func execute(context:GraphExecutionContext,
                 renderPassDescriptor: MTLRenderPassDescriptor,
                 commandBuffer: MTLCommandBuffer)
    
    func resize(size: (width: Float, height: Float), scaleFactor: Float)
    
    func markDirty()
    func markClean()
    var isDirty:Bool { get }

    // For the Graph
    func publishedPorts() -> [any NodePortProtocol]
    // For the UI
    func publishedParameterPorts() -> [any NodePortProtocol]

    func inputNodes() -> [any NodeProtocol]
    func outputNodes() -> [any NodeProtocol]
    
    var offset: CGSize { get set }
    var nodeSize: CGSize { get }
    
    
    var isSelected:Bool { get set}
    var isDragging:Bool { get set }
}

protocol NodeFileLoadingProtocol : NodeProtocol
{
    init(context:Context, fileURL:URL) throws
}

// Optional
public extension NodeProtocol
{
    func startExecution(context:GraphExecutionContext) { }
    func stopExecution(context:GraphExecutionContext) { }

    func enableExecution(context:GraphExecutionContext) { }
    func disableExecution(context:GraphExecutionContext) { }
    
    func execute(context:GraphExecutionContext,
                         renderPassDescriptor: MTLRenderPassDescriptor,
                         commandBuffer: MTLCommandBuffer)
    {

    }
}

@Observable public class Node :  Equatable, Identifiable, Hashable
{
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
    
    @ObservationIgnored public var inputParameters:[any Parameter] { []  }
    @ObservationIgnored public let parameterGroup:ParameterGroup = ParameterGroup("Parameters", [])
                                                        
    @ObservationIgnored private var inputParameterPorts:[any NodePortProtocol] = []
    
    public var ports:[any NodePortProtocol] { self.inputParameterPorts  }

    @ObservationIgnored var context:Context
            
    public var isSelected:Bool = false
    public var isDragging:Bool = false
//    var showParams:Bool = false

    @ObservationIgnored public var nodeType:NodeType {
        let myType = type(of: self) as! (any NodeProtocol.Type)
        return  myType.nodeType
    }
    
    public var name : String {
        let myType = type(of: self) as! (any NodeProtocol.Type)
        return  myType.name
    }
    
    public var nodeSize:CGSize { self.computeNodeSize() } //CGSizeMake(150, 100)

    public var offset: CGSize = .zero
//    {
//        willSet
//        {
//            if let delegate = self.delegate
//            {
//                delegate.willUpdate(node: self)
//            }
//        }
//        
//        didSet
//        {
//            if let delegate = self.delegate
//            {
//                delegate.didUpdate(node: self)
//            }
//        }
//    }
    
    // Dirty Handling
//    @ObservationIgnored var lastEvaluationTime: TimeInterval = -1
    @ObservationIgnored public var isDirty: Bool = true
    
    // Input Parameter update tracking:
    @ObservationIgnored var inputParamCancellables: [AnyCancellable] = []
    
    enum CodingKeys : String, CodingKey
    {
        case id
        case inputParameters
        case nodeOffset
        case valuePorts
    }

    
    required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        self.context = decodeContext.documentContext
        
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.offset = try container.decode(CGSize.self, forKey: .nodeOffset)

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
            port.node = self as? (any NodeProtocol)
        }
        
//        self.nodeSize = self.computeNodeSize()
    }

    func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        try container.encode(self.offset, forKey: .nodeOffset)

        try container.encode(self.parameterGroup, forKey: .inputParameters)
    }
    
    required init (context:Context)
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
        
        for var port in self.ports
        {
            port.node = self as? (any NodeProtocol)
        }
        
//        self.nodeSize = self.computeNodeSize()
    }
    
    deinit
    {
        self.inputParamCancellables.forEach { $0.cancel() }
        
        print("Deleted node \(id)")
    }
    
    
    public func inputNodes() -> [any NodeProtocol]
    {
        let nodeInputs = self.ports.filter( { $0.kind == .Inlet } )
        let inputNodes = nodeInputs.compactMap { $0.connections.compactMap(\.node) }.flatMap(\.self)
  
        return inputNodes
//        return Array(Set(inputNodes))
    }
    
    public func outputNodes() -> [any NodeProtocol]
    {
        let nodeOutputs = self.ports.filter( { $0.kind == .Outlet } )
        let outputNodes = nodeOutputs.compactMap { $0.connections.compactMap(\.node) }.flatMap(\.self)
  
        return outputNodes
//        return Array(Set(outputNodes))
    }
    
    public func publishedPorts() -> [any NodePortProtocol]
    {
        return self.ports.filter( { $0.published } )
    }
    
    public func publishedParameterPorts() -> [any NodePortProtocol]
    {
        return self.inputParameterPorts.filter( { $0.published } )
    }
    
    public func markClean()
    {
        isDirty = false
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
    
    public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        
    }
   
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
    
    private func parametersGroupToPorts(_ parameters:[(any Parameter)]) -> [any NodePortProtocol]
    {
        print(self.name, "parametersGroupToPorts")
        return parameters.compactMap( {
            self.parameterToPort(parameter:$0) })
    }
    
    private func parameterToPort(parameter:(any Parameter)) -> (any NodePortProtocol)?
    {
        print(self.name, "parameterToPort", parameter.label)
                
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
