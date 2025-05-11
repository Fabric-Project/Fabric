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

protocol NodeProtocol : Codable
{
    init(context:Context)
    
    static var name:String { get }
    static var nodeType:Node.NodeType { get }
    var nodeType:Node.NodeType { get }

    var ports: [any NodePortProtocol] { get }
    var parameterGroup:ParameterGroup { get }
    func evaluate(atTime:TimeInterval,
                  renderPassDescriptor: MTLRenderPassDescriptor,
                  commandBuffer: MTLCommandBuffer)
    
//    func update()
    func resize(size: (width: Float, height: Float), scaleFactor: Float)
    

}

@Observable class Node :  Equatable, Identifiable, Hashable
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
                                                        
    @ObservationIgnored private var inputParameterPorts:[any NodePortProtocol] = []
    @ObservationIgnored var ports:[any NodePortProtocol] { self.inputParameterPorts  }
        
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
        
        let parameterGroup = try container.decode(ParameterGroup.self, forKey: .inputParameters)
        self.parameterGroup.copy( parameterGroup )
        
        self.inputParameterPorts = self.parametersGroupToPorts(self.inputParameters)

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
            port.node = self
        }
        
        self.nodeSize = self.computeNodeSize()
    }
    
    deinit
    {
        self.inputParamCancellables.forEach { $0.cancel() }
        
        print("Deleted node \(id)")
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
    
    public func markDirty()
    {
        isDirty = true
        
        self.outputNodes().forEach( { $0.markDirty() } )
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
