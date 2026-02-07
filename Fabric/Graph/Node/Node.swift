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


@Observable public class Node : Codable, Equatable, Identifiable, Hashable, Copyable
{
    // User interface name
    public class var name: String {  fatalError("\(String(describing:self)) Must implement name") }
    
    // Custom name (rename)
    public var displayName: String?
    
    // User interface organizing principle
    public class var nodeType:Node.NodeType { fatalError("\(String(describing:self)) Must implement nodeType") }
    
    // Execution mode value is used to determine when this node is evaluated
    public class var nodeExecutionMode: Node.ExecutionMode { fatalError("\(String(describing:self)) Must implement nodeExecutionMode") }

    // Execution mode value is used to determine when this node is evaluated
    public class var nodeTimeMode: Node.TimeMode {  fatalError("\(String(describing:self)) Must implement nodeTimeMode") }

    // User interface description
    public class var nodeDescription: String { fatalError("\(String(describing:self)) Must implement nodeDescription") }

    // Identifiable
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
        return displayName ?? myType.name
    }
    
    @ObservationIgnored public var nodeType:NodeType
    {
        return Self.nodeType
    }
    
    @ObservationIgnored public var nodeExecutionMode:ExecutionMode
    {
        return Self.nodeExecutionMode
    }
    
    @ObservationIgnored public var context:Context

    @ObservationIgnored public weak var graph:Graph?

    // Method to register ports
    public class func registerPorts(context: Context) -> [(name: String, port: Port)] { [] }
    // All port serilization, adding, removing and key value access goes through the port registry
    @ObservationIgnored private let registry = PortRegistry()
    
    // Sadly this needs to be observed
    public let parameterGroup:ParameterGroup = ParameterGroup("Parameters", [])

    public var ports:[Port] { self.registry.all()   }
    public private(set) var inputNodes:[Node] = []
    public private(set) var outputNodes:[Node]  = []
    
    public var isSelected:Bool = false
    public var isDragging:Bool = false
    // var showParams:Bool = false
    
    internal var showSettings:Bool = false

    public var nodeSize:CGSize { self.computeNodeSize() }
    
    public var offset: CGSize = .zero
    
    // Dirty Handling
    // @ObservationIgnored var lastEvaluationTime: TimeInterval = -1
    @ObservationIgnored private(set) public var isDirty: Bool = true
    
    // Input Parameter update tracking:
    @ObservationIgnored var inputParamCancellables: [AnyCancellable] = []

    
    // MARK: - Serialization and Init
    enum CodingKeys : String, CodingKey
    {
        case id
        case nodeOffset
        case ports
        
        // TODO:
        case name // Override node UI name (not implemented)
        case displayName

        // Depreciated...
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
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
  
        let snaps = try container.decodeIfPresent([PortRegistry.Snapshot].self, forKey: .ports) ?? []

        for snap in snaps
        {
            let anyport  = snap.payload
            let port = anyport.base
            
            self.registry.register(port, name: snap.name, owner: self)
        }
        
        // lets try to merge if we have any ports we deserialized
        // that our node should have registered (ie diff)
        let declared = Self.registerPorts(context: context)

        for d in declared
        {
            if let _ = self.registry.port(named: d.name)
            {
                continue
            }
            else
            {
                self.registry.register(d.port, name: d.name, owner: self)
            }
        }
   
        
        for port in self.registry.all()
        {
            if let param = port.parameter
            {
                self.parameterGroup.append(param)
            }
        }
        self.synchronizeParameters()
        
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
        try container.encode(self.registry.encode(), forKey: .ports)
        try container.encodeIfPresent(self.displayName, forKey: .displayName)
    }
    
    public required init(context:Context)
    {
        self.id = UUID()
        self.context = context
        
        let declared = Self.registerPorts(context: context)
        for (name, p) in declared {
            self.registry.register(p, name: name, owner: self)
        }
        
        for port in self.registry.all()
        {
            if let param = port.parameter
            {
                self.parameterGroup.append(param)
            }
        }
        
        self.synchronizeParameters()
        
        for port in self.ports
        {
            port.node = self
        }
    }
    
    deinit
    {
        print("Deleted node \(id)")
    }
    
    
    // This function clears references to other nodes and node ports
    // removing any circular references allowing proper cleanup
    // This must is called by GraphRenderer.
    public func teardown()
    {
        self.inputNodes.removeAll()
        self.outputNodes.removeAll()
        
        for port in self.ports
        {
            port.disconnectAll()
            port.teardown()
        }
        
        self.inputParamCancellables.forEach { $0.cancel() }
        self.inputParamCancellables.removeAll()
    }
    
    // MARK: - Ports
    
    // Convenience for subclasses: typed lookup (so computed props stay nice)
    public func port<T: Port>(named name: String, as type: T.Type = T.self) -> T
    {
        self.registry.port(named: name) as! T
    }
    
    // Convenience for subclasses: typed lookup (so computed props stay nice)
    public func findPort<T: Port>(named name: String, as type: T.Type = T.self) -> T?
    {
        self.registry.port(named: name) as? T
    }
    
    // Dynamic add/remove (kept by serialization automatically)
    public func addDynamicPort(_ p: Port, name:String? = nil)
    {
        self.registry.addDynamic(p, owner: self, name:name)
        if let param = p.parameter
        {
            self.parameterGroup.append(param)
        }
        
        self.graph?.shouldUpdateConnections.toggle()
    }
    
    public func removePort(_ p: Port)
    {
        self.registry.remove(p)
        if let param = p.parameter
        {
            self.parameterGroup.remove(param)
        }
        
        self.graph?.shouldUpdateConnections.toggle()
    }
    
    public func replaceParameterOfPort(_ port:Port, withParam param:(any Parameter))
    {
        // Remove existing param from group
        if let existingParam = port.parameter
        {
            self.parameterGroup.remove(existingParam)
        }
        
        // Add new param to group
        self.parameterGroup.append(param)
        
        port.parameter = param
    }
    
//    public func syncPort(p:Port)
//    {
//        self.registry.rebuild(from: <#T##[PortRegistry.Snapshot]#>, declared: <#T##[(name: String, port: Port)]#>, owner: <#T##Node#>)
//    }
    
    public func inputPorts() -> [Port]
    {
        return self.ports.filter( { $0.kind == .Inlet } )
    }
    
    public func outputPorts() -> [Port]
    {
        return self.ports.filter( { $0.kind == .Outlet } )
    }
    
    public func publishedPorts() -> [Port]
    {
        return self.ports.filter( { $0.published } )
    }
    
    public func publishedInputPorts() -> [Port]
    {
        return self.inputPorts().filter( { $0.published } )
    }
    
    public func publishedOutputPorts() -> [Port]
    {
        return self.outputPorts().filter( { $0.published  } )
    }
    
    // MARK: - Connections
        
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
    
    public func synchronizeParameters()
    {
        self.inputParamCancellables.forEach( { $0.cancel() } )
        self.inputParamCancellables.removeAll()
        
        for parameter in self.parameterGroup.params
        {
            let cancellable = self.makeCancelable(parameter: parameter)
            
            self.inputParamCancellables.append(cancellable)
        }
    }
    
    private func makeCancelable(parameter: some Parameter) -> AnyCancellable
    {
        let cancellable = parameter.valuePublisher.eraseToAnyPublisher().sink{ [weak self] _ in
            self?.markDirty()
        }
        
        return cancellable
    }
    
    // MARK: - Execution
    
    public func startExecution(context:GraphExecutionContext) { }
    public func stopExecution(context:GraphExecutionContext) { }

    public func enableExecution(context:GraphExecutionContext) { }
    public func disableExecution(context:GraphExecutionContext) { }
    
    public func execute(context:GraphExecutionContext,
                         renderPassDescriptor: MTLRenderPassDescriptor,
                         commandBuffer: MTLCommandBuffer) { }
        
    public func resize(size: (width: Float, height: Float), scaleFactor: Float) { }
   
    // MARK: - Node Settings

    public enum SettingsViewSize
    {
        case Small
        case Medium
        case Large
        case Custom(size:CGSize)
        
        func size() -> CGSize
        {
            switch self
            {
            case .Small:
                return CGSize(width: 300, height: 200)
            case .Medium:
                return CGSize(width: 400, height: 300)
            case .Large:
                return CGSize(width: 500, height: 400)
            case .Custom(size: let size):
                return size
            }
        }
        
    }
    
    public func providesSettingsView() -> Bool
    {
        return false
    }
        
    internal struct NodeSettingView : View
    {
        var node: Node

        internal var body: some View
        {
            @Bindable var bindableNode:Node = node
            let size = node.settingsSize.size()

            VStack(alignment: .center)
            {
                HStack()
                {
                    Text("\(node.name) Settings" )
                        .lineLimit(1)
                        .font(.system(size: 10))
                        .bold()

                    Spacer()

                    Button("Close", systemImage: "x.circle") {
                        node.showSettings = false
                    }
                    .controlSize(.small)
                }

                Spacer()

                if node.providesSettingsView( )
                {
                    node.settingsView()
                }
            }
            .padding()
            .frame(width: size.width, height: size.height)
            .clipShape (
                RoundedRectangle(cornerRadius: 4)
            )
        }
    }
    
    public func settingsView() -> AnyView
    {
        AnyView(EmptyView())
    }
    
    public var settingsSize:SettingsViewSize { .Small }
    
    // MARK: - Helpers
    
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
