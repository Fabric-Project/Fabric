//
//  OSCReceiveNode.swift
//  Fabric
//
//  Created by Anton Marini / Claude Code on 1/25/26.
//

import Foundation
import SwiftUI
import Metal
internal import OSCKit
import Satin
import simd

// MARK: - OSC Address Binding

/// Represents a configured OSC address to listen for
public struct OSCAddressBinding: Codable, Equatable, Identifiable, Sendable
{
    public let id: UUID
    public var address: String
    public var dataType: OSCDataType

    public init(address: String = "/example", dataType: OSCDataType = .float)
    {
        self.id = UUID()
        self.address = address
        self.dataType = dataType
    }

    public init(id: UUID, address: String, dataType: OSCDataType)
    {
        self.id = id
        self.address = address
        self.dataType = dataType
    }
}

public enum OSCDataType: String, Codable, CaseIterable, Sendable
{
    case float = "Float"
    case int = "Int"
    case string = "String"
    case bool = "Bool"

    var portType: Any.Type
    {
        switch self
        {
        case .float: return Float.self
        case .int: return Int.self
        case .string: return String.self
        case .bool: return Bool.self
        }
    }
}

// MARK: - Settings

/// The settings of an OSC Receive node: the port it listens on and the
/// addresses it hands out, one output each.
public struct OSCReceiveSettings: NodeSettings
{
    public var listenPort: UInt16
    public var addressBindings: [OSCAddressBinding]

    public init(listenPort: UInt16, addressBindings: [OSCAddressBinding])
    {
        self.listenPort = listenPort
        self.addressBindings = addressBindings
    }
}

// MARK: - Settings View

struct OSCAddressConfigView: View
{
    @Bindable var model: OSCReceiveNode.SettingsModel
    let bindingID: UUID

    private var bindingIndex: Int?
    {
        model.addressBindings.firstIndex(where: { $0.id == bindingID })
    }

    var body: some View
    {
        if let index = bindingIndex
        {
            HStack
            {
                TextField("Address", text: Binding(
                    get: { model.addressBindings[index].address },
                    set: { newValue in
                        model.addressBindings[index].address = newValue
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 10))
                .onSubmit { model.endEditing() }

                Picker("", selection: Binding(
                    get: { model.addressBindings[index].dataType },
                    set: { newValue in
                        model.addressBindings[index].dataType = newValue
                        model.endEditing()
                    }
                ))
                {
                    ForEach(OSCDataType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)

                Button(action: {
                    model.removeAddressBinding(id: bindingID)
                }) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct OSCReceiveNodeView: View
{
    @Bindable var model: OSCReceiveNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Text("OSC Receive Configuration")
                .font(.system(size: 10))
                .bold()

            HStack
            {
                Text("Port:")
                    .font(.system(size: 10))

                TextField("Port", value: $model.listenPort, format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 10))
                    .frame(width: 80)

                Spacer()

                Button(model.isListening ? "Stop" : "Start")
                {
                    if model.isListening
                    {
                        model.stopListening()
                    }
                    else
                    {
                        model.startListening()
                    }
                }
                .controlSize(.small)
            }

            Divider()

            Text("Address Bindings:")
                .font(.system(size: 10))

            ScrollView
            {
                VStack(alignment: .leading, spacing: 4)
                {
                    ForEach(model.addressBindings) { binding in
                        OSCAddressConfigView(model: model, bindingID: binding.id)
                    }
                }
            }
            .frame(maxHeight: 150)

            HStack
            {
                Spacer()

                Button("+")
                {
                    model.addAddressBinding()
                }
                .controlSize(.small)

                Spacer()
            }

            Spacer()
        }
        .padding(4)
        .onDisappear { model.endEditing() }
    }
}

// MARK: - OSC Receive Node

public class OSCReceiveNode: Node
{
    override public static var name: String { "OSC Receive" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .IO) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Receive OSC messages and output values" }

    // MARK: - Codable

    private enum OSCReceiveCodingKeys: String, CodingKey
    {
        case listenPort
        case addressBindings
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: OSCReceiveCodingKeys.self)

        self.listenPort = try container.decodeIfPresent(UInt16.self, forKey: .listenPort) ?? 9000
        let decodedBindings = try container.decodeIfPresent([OSCAddressBinding].self, forKey: .addressBindings)
        self.addressBindings = decodedBindings ?? []

        // Rebuild ports based on restored bindings
        self.rebuildPorts()
    }

    override public var settings: (any NodeSettings)?
    {
        OSCReceiveSettings(listenPort: listenPort, addressBindings: addressBindings)
    }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? OSCReceiveSettings else { return }
        // Setting the port restarts a running listener.
        if settings.listenPort != listenPort { listenPort = settings.listenPort }
        if settings.addressBindings != addressBindings { addressBindings = settings.addressBindings }
        super.apply(settings)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public convenience init(context: Context, listenPort: UInt16, addressBindings: [OSCAddressBinding] = [])
    {
        self.init(context: context)
        self.listenPort = listenPort
        self.addressBindings = addressBindings
        self.rebuildPorts()
    }

    public convenience init(context: Context, settings: OSCReceiveSettings)
    {
        self.init(context: context, listenPort: settings.listenPort, addressBindings: settings.addressBindings)
    }

    // MARK: - Properties

    fileprivate private(set) var listenPort: UInt16 = 9000
    {
        didSet
        {
            // Restart listening if port changes while listening
            if isListening
            {
                stopListening()
                try? startListening()
            }
        }
    }

    fileprivate private(set) var addressBindings: [OSCAddressBinding] = []
    {
        didSet { self.rebuildPorts() }
    }

    private var oscServer: OSCServer?
    fileprivate var isListening: Bool = false

    // Store latest values for each address
    private var latestValues: [String: Any] = [:]

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        // The settings view is made on the main thread.
        if _settingsModelStorage == nil { _settingsModelStorage = MainActor.assumeIsolated { SettingsModel(node: self) } }
        return AnyView(OSCReceiveNodeView(model: _settingsModelStorage!))
    }

    override public var settingsSize: SettingsViewSize { .Medium }

    // MARK: - Settings Model

    /// The view's draft of the port and addresses: a typed address is
    /// committed after a pause or as editing ends, anything else as it is
    /// made. Whether the node listens is the node's.
    // Not isolated as a whole: the node sets the lists and runtime state it
    // shows from wherever they change. What touches the draft is main-thread.
    @Observable final class SettingsModel
    {
        let draft: NodeSettingsDraft<OSCReceiveSettings>

        @MainActor var listenPort: UInt16
        {
            get { draft.value.listenPort }
            set
            {
                draft.value.listenPort = newValue
                draft.commit()
            }
        }

        @MainActor var addressBindings: [OSCAddressBinding]
        {
            get { draft.value.addressBindings }
            set { draft.value.addressBindings = newValue }
        }

        var isListening: Bool = false

        @ObservationIgnored private weak var node: OSCReceiveNode?

        @MainActor init(node: OSCReceiveNode)
        {
            self.node = node
            self.draft = NodeSettingsDraft(of: OSCReceiveSettings(listenPort: node.listenPort, addressBindings: node.addressBindings),
                                           on: node,
                                           commit: .afterPause)
            self.isListening = node.isListening
        }

        func startListening() { try? node?.startListening(); isListening = node?.isListening ?? false }
        func stopListening() { node?.stopListening(); isListening = false }

        @MainActor func addAddressBinding()
        {
            draft.value.addressBindings.append(OSCAddressBinding(address: "/osc/\(addressBindings.count + 1)", dataType: .float))
            draft.commit()
        }

        @MainActor func removeAddressBinding(id: UUID)
        {
            draft.value.addressBindings.removeAll { $0.id == id }
            draft.commit()
        }

        /// Commits what typing has left in the draft.
        @MainActor func endEditing() { draft.commit() }
    }

    private var _settingsModelStorage: SettingsModel? = nil

    // MARK: - Lifecycle

    public override func enableExecution(renderer: GraphRenderer)
    throws
    {
        try startListening()
        try super.enableExecution(renderer: renderer)
    }

    public override func disableExecution(renderer: GraphRenderer)
    throws
    {
        stopListening()
        try super.disableExecution(renderer: renderer)
    }

    // MARK: - Execution

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        // Send latest values to ports
        for binding in addressBindings
        {
            let portName = portNameForAddress(binding.address)
            guard let value = latestValues[binding.address] else { continue }

            switch binding.dataType
            {
            case .float:
                if let port = self.findPort(named: portName) as? NodePort<Float>,
                   let floatValue = value as? Float
                {
                    port.send(floatValue)
                }

            case .int:
                if let port = self.findPort(named: portName) as? NodePort<Int>,
                   let intValue = value as? Int
                {
                    // Convert to Float for now since we commonly use Float ports
                    port.send(intValue)
                }

            case .string:
                if let port = self.findPort(named: portName) as? NodePort<String>,
                   let stringValue = value as? String
                {
                    port.send(stringValue)
                }

            case .bool:
                if let port = self.findPort(named: portName) as? NodePort<Bool>,
                   let boolValue = value as? Bool
                {
                    port.send(boolValue)
                }
            }
        }
    }

    // MARK: - OSC Server Management

    fileprivate func startListening() throws
    {
        guard !isListening else { return }

        do
        {
            oscServer = OSCServer(port: listenPort) { [weak self] message, _ in
                self?.handleOSCMessage(message)
            }
            try oscServer?.start()
            isListening = true
            _settingsModelStorage?.isListening = true
            print("OSC Server started on port \(listenPort)")
        }
        catch
        {
            isListening = false
            _settingsModelStorage?.isListening = false
            throw FabricError(.execution(.failed),
                              severity: .recoverable,
                              message: "Failed to start OSC server on port \(listenPort)",
                              underlyingError: error)
        }
    }

    fileprivate func stopListening()
    {
        oscServer?.stop()
        oscServer = nil
        isListening = false
        _settingsModelStorage?.isListening = false
        print("OSC Server stopped")
    }

    private func handleOSCMessage(_ message: OSCMessage)
    {
        let address = message.addressPattern.stringValue

        // Check if we're listening for this address
        guard let binding = addressBindings.first(where: { $0.address == address }) else { return }

        // Extract the first argument value based on expected type
        guard let firstArg = message.values.first else { return }

        switch binding.dataType
        {
        case .float:
            if let value = firstArg as? Float
            {
                latestValues[address] = value
            }
            else if let value = firstArg as? Double
            {
                latestValues[address] = Float(value)
            }

        case .int:
            if let value = firstArg as? Int32
            {
                latestValues[address] = Int(value)
            }
            else if let value = firstArg as? Int
            {
                latestValues[address] = value
            }

        case .string:
            if let value = firstArg as? String
            {
                latestValues[address] = value
            }

        case .bool:
            if let value = firstArg as? Bool
            {
                latestValues[address] = value
            }
            else if let value = firstArg as? Int32
            {
                latestValues[address] = value != 0
            }
        }

        self.markDirty()
    }

    // MARK: - Address Binding Management

    // MARK: - Port Management

    private func rebuildPorts()
    {
        self.reconcilePorts()
    }

    /// An outlet of its type for each bound address, in binding order.
    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + addressBindings.map { binding in
            let portName = portNameForAddress(binding.address)
            let port: Port
            switch binding.dataType
            {
            case .float:
                port = NodePort<Float>(name: portName, kind: .Outlet, description: "OSC float value received at \(binding.address)")
            case .int:
                port = NodePort<Int>(name: portName, kind: .Outlet, description: "OSC integer value received at \(binding.address)")
            case .string:
                port = NodePort<String>(name: portName, kind: .Outlet, description: "OSC string value received at \(binding.address)")
            case .bool:
                port = NodePort<Bool>(name: portName, kind: .Outlet, description: "OSC boolean value received at \(binding.address)")
            }
            return PortDeclaration(registryKey: portName, port: port)
        }
    }

    private func portNameForAddress(_ address: String) -> String
    {
        // Clean up address to make valid port name
        // Remove leading slash and replace remaining slashes with underscores
        var name = address
        if name.hasPrefix("/")
        {
            name = String(name.dropFirst())
        }
        name = name.replacingOccurrences(of: "/", with: "_")
        return name
    }
}
