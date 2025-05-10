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

protocol NodeDelegate : AnyObject
{
    func willUpdate(node:Node)
    func didUpdate(node:Node)
    func shouldDelete(node:Node)
}

protocol NodeProtocol
{
    init(context:Context)
    
    static var name:String { get }
    static var nodeType:Node.NodeType { get }
    var nodeType:Node.NodeType { get }

    var ports: [any AnyPort] { get }
    var parameterGroup:ParameterGroup { get }
    func evaluate(atTime:TimeInterval,
                  renderPassDescriptor: MTLRenderPassDescriptor,
                  commandBuffer: MTLCommandBuffer)
    
//    func update()
    func resize(size: (width: Float, height: Float), scaleFactor: Float)
    

}

@Observable class Node: Equatable, Identifiable, Hashable, Codable
{
    enum NodeType : String, CaseIterable
    {
        case Texture // Rendered output of a Renderer
        case Renderer // Renders a scene graph
        case Object // Scene graph, owns transforms
        case Camera // Scene graph object
        case Light // Scene graph object
        case Mesh // Scene graph object
        case Geometery
        case Material
        case Shader
        
        case Parameter
        
        func color() -> Color
        {
            switch self
            {
            case .Texture:
                return Color.nodeTexture

            case .Geometery:
                return Color.nodeGeometry

            case .Camera:
                return Color.nodeCamera
                
            case .Light:
                return Color.nodeObject

            case .Material:
                return Color.nodeMaterial

            case .Mesh:
                return Color.nodeMesh
                
            case .Renderer:
                return Color.nodeRender

            case .Shader:
                return Color.nodeShader
                
            case .Object:
                return Color.nodeObject
                
            case .Parameter:
                return Color(hue: 0, saturation: 0, brightness: 0.3)
            }
        }
        
        func backgroundColor() -> Color
        {
            return self.color().opacity(0.6)
        }
    }
        
    // Equatable
    let id:UUID
    
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
    
    
    @ObservationIgnored var inputParameters:[any Parameter] { []  }
    @ObservationIgnored let parameterGroup:ParameterGroup = ParameterGroup("Parameters", [])
                                                        
    @ObservationIgnored private var inputParameterPorts:[any AnyPort] = []
    @ObservationIgnored var ports:[any AnyPort] { self.inputParameterPorts  }
        
    var nodeSize:CGSize = CGSizeMake(150, 100)

    @ObservationIgnored var context:Context
    
    @ObservationIgnored weak var delegate:(any NodeDelegate)? = nil
        
    var isSelected:Bool = false
    var isDragging:Bool = false
    var showParams:Bool = false

    @ObservationIgnored public var nodeType:NodeType {
        let myType = type(of: self) as! (any NodeProtocol.Type)
        return  myType.nodeType
    }
    
    var name : String {
        let myType = type(of: self) as! (any NodeProtocol.Type)
        return  myType.name
    }
    
    var offset: CGSize = .zero
    {
        willSet
        {
            if let delegate = self.delegate
            {
                delegate.willUpdate(node: self)
            }
        }
        
        didSet
        {
            if let delegate = self.delegate
            {
                delegate.didUpdate(node: self)
            }
        }
    }
    
    // Dirty Handling
    @ObservationIgnored var lastEvaluationTime: TimeInterval = -1
    @ObservationIgnored var isDirty: Bool = true
    
    @ObservationIgnored var inputParamCancellables: [AnyCancellable] = []
    public func markDirty() {
        isDirty = true
        
        self.outputNodes().forEach( { $0.markDirty() } )
        
//        print(self.name, "is dirty")
    }
    
    func inputNodes() -> [Node]
    {
        let nodeInputs = self.ports.filter( { $0.kind == .Inlet } )
        let inputNodes = nodeInputs.compactMap { $0.connections.compactMap(\.node) }.flatMap(\.self)
        
        return inputNodes
    }
    
    func outputNodes() -> [Node]
    {
        let nodeOutputs = self.ports.filter( { $0.kind == .Outlet } )
        let outputNodes = nodeOutputs.compactMap { $0.connections.compactMap(\.node) }.flatMap(\.self)
        
        return outputNodes
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
            port.node = self
        }
        
        self.nodeSize = self.computeNodeSize()
    }
    
    deinit
    {
        self.inputParamCancellables.forEach { $0.cancel() }
        
        print("Deleted node \(id)")
    }
    
    private func makeCancelable(parameter: some Parameter) -> AnyCancellable
    {
        let cancellable = parameter.valuePublisher.eraseToAnyPublisher().sink{ [weak self] _ in
            self?.markDirty()
        }
        
        return cancellable
    }
    public func evaluate(atTime:TimeInterval,
                         renderPassDescriptor: MTLRenderPassDescriptor,
                         commandBuffer: MTLCommandBuffer)
    {

    }
    
    public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        
    }
   
    private func computeNodeSize() -> CGSize
    {
        let horizontalInputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Inlet  }.count
        let horizontalOutputsCount = self.ports.filter { $0.direction == .Horizontal && $0.kind != .Outlet  }.count

        let verticalInputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Inlet  }.count
        let verticalOutputsCount = self.ports.filter { $0.direction == .Vertical && $0.kind != .Outlet  }.count

        let horizontalMax = max(horizontalInputsCount, horizontalOutputsCount)
        let verticalMax = max(verticalInputsCount, verticalOutputsCount)
        
        let height:CGFloat = 20 + (CGFloat(horizontalMax) * 25)
        let width:CGFloat = 20 + (CGFloat(verticalMax) * 25)
        
        return CGSize(width: max(width, 150), height: max(height, 60) )
    }
    
    // Mark - Private helper
    
    private func parametersGroupToPorts(_ parameters:[(any Parameter)]) -> [any AnyPort]
    {
        print(self.name, "parametersGroupToPorts")
        return parameters.compactMap( {
            self.parameterToPort(parameter:$0) })
    }
    
    private func parameterToPort(parameter:(any Parameter)) -> (any AnyPort)?
    {

        print(self.name, "parameterToPort", parameter.label)

        
                
        switch parameter.type
        {
            
        case .generic:
            
            if let genericParam = parameter as? GenericParameter<Float>
            {
                return ParameterNode(parameter: genericParam)
            }
            
            if let genericParam = parameter as? GenericParameter<simd_float3>
            {
                return ParameterNode(parameter: genericParam)
            }
            
            if let genericParam = parameter as? GenericParameter<simd_float4>
            {
                return ParameterNode(parameter: genericParam)
            }
            
            if let genericParam = parameter as? GenericParameter<simd_quatf>
            {
                return ParameterNode(parameter: genericParam)
            }
            
        case .string:
            
            if let genericParam = parameter as? StringParameter
            {
                return ParameterNode(parameter: genericParam)
            }

        case .bool:

            if let genericParam = parameter as? BoolParameter
            {
                return ParameterNode(parameter: genericParam)
            }
            
        case .float:
            
            if let genericParam = parameter as? FloatParameter
            {
                return ParameterNode(parameter: genericParam)
            }

            else if let genericParam = parameter as? GenericParameter<Float>
            {
                return ParameterNode(parameter: genericParam)
            }

        case .float2:
            if let genericParam = parameter as? Float2Parameter
            {
                return ParameterNode(parameter: genericParam)
            }
            
        case .float3:
            if let genericParam = parameter as? Float3Parameter
            {
                return ParameterNode(parameter: genericParam)
            }
            
        case .float4:
            if let genericParam = parameter as? Float4Parameter
            {
                return ParameterNode(parameter: genericParam)
            }
            
            else if let genericParam = parameter as? GenericParameter<simd_float4>
            {
                return ParameterNode(parameter: genericParam)
            }
            
        case .float2x2:
            if let genericParam = parameter as? Float2x2Parameter
            {
                return ParameterNode(parameter: genericParam)
            }
            
        case .float3x3:
            if let genericParam = parameter as? Float3x3Parameter
            {
                return ParameterNode(parameter: genericParam)
            }

        case .float4x4:
            if let genericParam = parameter as? Float4x4Parameter
            {
                return ParameterNode(parameter: genericParam)
            }

        default:
            return nil

        }
        
        return nil

    }
}
