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
public struct OSCAddressBinding: Codable, Equatable, Identifiable
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

public enum OSCDataType: String, Codable, CaseIterable
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

                Picker("", selection: Binding(
                    get: { model.addressBindings[index].dataType },
                    set: { newValue in
                        model.addressBindings[index].dataType = newValue
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

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: OSCReceiveCodingKeys.self)
        try container.encode(self.listenPort, forKey: .listenPort)
        try container.encode(self.addressBindings, forKey: .addressBindings)
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

    // MARK: - Properties

    fileprivate var listenPort: UInt16 = 9000
    {
        didSet
        {
            // Restart listening if port changes while listening
            if isListening
            {
                stopListening()
                try? startListening()
            }
            _settingsModelStorage?.listenPort = listenPort
        }
    }

    fileprivate var addressBindings: [OSCAddressBinding] = []
    {
        didSet
        {
            self.rebuildPorts()
            _settingsModelStorage?.addressBindings = addressBindings
        }
    }

    private var oscServer: OSCServer?
    fileprivate var isListening: Bool = false

    // Store latest values for each address
    private var latestValues: [String: Any] = [:]

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        if _settingsModelStorage == nil { _settingsModelStorage = SettingsModel(node: self) }
        return AnyView(OSCReceiveNodeView(model: _settingsModelStorage!))
    }

    override public var settingsSize: SettingsViewSize { .Medium }

    // MARK: - Settings Model

    @Observable final class SettingsModel
    {
        var listenPort: UInt16
        {
            didSet
            {
                guard listenPort != node?.listenPort else { return }
                node?.listenPort = listenPort
            }
        }
        var addressBindings: [OSCAddressBinding]
        {
            didSet
            {
                guard addressBindings != node?.addressBindings else { return }
                node?.addressBindings = addressBindings
            }
        }
        var isListening: Bool = false

        private weak var node: OSCReceiveNode?

        init(node: OSCReceiveNode)
        {
            self.node = node
            self.listenPort = node.listenPort
            self.addressBindings = node.addressBindings
            self.isListening = node.isListening
        }

        func startListening() { try? node?.startListening(); isListening = node?.isListening ?? false }
        func stopListening() { node?.stopListening(); isListening = false }
        func addAddressBinding() { node?.addAddressBinding() }
        func removeAddressBinding(id: UUID) { node?.removeAddressBinding(id: id) }
    }

    private var _settingsModelStorage: SettingsModel? = nil

    // MARK: - Lifecycle

    public override func enableExecution(renderer: GraphRenderer)
    throws
    {
        try startListening()
    }

    public override func disableExecution(renderer: GraphRenderer)
    throws
    {
        stopListening()
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

    fileprivate func addAddressBinding()
    {
        let newBinding = OSCAddressBinding(address: "/osc/\(addressBindings.count + 1)", dataType: .float)
        addressBindings.append(newBinding)
    }

    fileprivate func removeAddressBinding(id: UUID)
    {
        addressBindings.removeAll(where: { $0.id == id })
    }

    // MARK: - Port Management

    private func rebuildPorts()
    {
        let portNamesWeNeed = addressBindings.map { portNameForAddress($0.address) }
        let existingPortNames = self.outputPorts().map { $0.name }

        let portsNamesToRemove = Set(existingPortNames).subtracting(Set(portNamesWeNeed))

        // Remove ports that are no longer needed
        for portName in portsNamesToRemove
        {
            if let port = self.findPort(named: portName)
            {
                self.removePort(port)
            }
        }

        // Add or update ports
        for binding in addressBindings
        {
            let portName = portNameForAddress(binding.address)

            // Remove existing port if type changed
            if let existingPort = self.findPort(named: portName)
            {
                // Check if type matches, if not remove and recreate
                let typeMatches: Bool
                switch binding.dataType
                {
                case .float:
                    typeMatches = existingPort is NodePort<Float>
                case .int:
                    typeMatches = existingPort is NodePort<Int>
                case .string:
                    typeMatches = existingPort is NodePort<String>
                case .bool:
                    typeMatches = existingPort is NodePort<Bool>
                }

                if !typeMatches
                {
                    self.removePort(existingPort)
                }
                else
                {
                    continue // Port exists and type matches
                }
            }

            // Create new port
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

            self.addDynamicPort(port)
            print("Added OSC port: \(portName)")
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
