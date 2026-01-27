//
//  MIDIInputNode.swift
//  Fabric
//
//  Created by Claude Code on 1/27/26.
//

import Foundation
import SwiftUI
import Metal
import MIDIKit

// MARK: - MIDI Binding Types

public enum MIDIBindingType: String, Codable, CaseIterable
{
    case noteGate = "Note Gate"
    case noteVelocity = "Note Velocity"
    case controlChange = "Control Change"
    case pitchBend = "Pitch Bend"
    case aftertouch = "Aftertouch"

    var description: String { rawValue }
}

/// Represents a configured MIDI binding
public struct MIDIBinding: Codable, Equatable, Identifiable
{
    public let id: UUID
    public var type: MIDIBindingType
    public var channel: Int // 1-16, or 0 for "any"
    public var number: Int  // Note number or CC number (0-127)
    public var name: String // Custom port name

    public init(type: MIDIBindingType = .controlChange, channel: Int = 0, number: Int = 1, name: String = "")
    {
        self.id = UUID()
        self.type = type
        self.channel = channel
        self.number = number
        self.name = name
    }

    public var defaultName: String
    {
        let channelStr = channel == 0 ? "" : "Ch\(channel) "
        switch type
        {
        case .noteGate:
            return "\(channelStr)Note \(number) Gate"
        case .noteVelocity:
            return "\(channelStr)Note \(number) Vel"
        case .controlChange:
            return "\(channelStr)CC \(number)"
        case .pitchBend:
            return "\(channelStr)Pitch Bend"
        case .aftertouch:
            return "\(channelStr)Aftertouch"
        }
    }

    public var displayName: String
    {
        name.isEmpty ? defaultName : name
    }
}

// MARK: - MIDI Input Info

public struct MIDIInputInfo: Codable, Equatable, Identifiable, Hashable
{
    public let id: String
    public let name: String
    public let manufacturer: String?

    public var displayName: String
    {
        if let manufacturer = manufacturer, !manufacturer.isEmpty
        {
            return "\(manufacturer) - \(name)"
        }
        return name
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
}

// MARK: - Settings View

struct MIDIBindingConfigView: View
{
    @Bindable var node: MIDIInputNode
    let bindingID: UUID

    private var bindingIndex: Int?
    {
        node.midiBindings.firstIndex(where: { $0.id == bindingID })
    }

    var body: some View
    {
        if let index = bindingIndex
        {
            HStack(spacing: 4)
            {
                // Type picker
                Picker("", selection: Binding(
                    get: { node.midiBindings[index].type },
                    set: { node.midiBindings[index].type = $0 }
                ))
                {
                    ForEach(MIDIBindingType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                // Channel
                Picker("", selection: Binding(
                    get: { node.midiBindings[index].channel },
                    set: { node.midiBindings[index].channel = $0 }
                ))
                {
                    Text("Any").tag(0)
                    ForEach(1...16, id: \.self) { ch in
                        Text("Ch \(ch)").tag(ch)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 65)

                // Number (for notes and CCs)
                if node.midiBindings[index].type == .noteGate ||
                   node.midiBindings[index].type == .noteVelocity ||
                   node.midiBindings[index].type == .controlChange
                {
                    TextField("#", value: Binding(
                        get: { node.midiBindings[index].number },
                        set: { node.midiBindings[index].number = max(0, min(127, $0)) }
                    ), format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 40)
                }

                // Remove button
                Button(action: {
                    node.removeBinding(id: bindingID)
                }) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
            .font(.system(size: 10))
        }
    }
}

struct MIDIInputNodeView: View
{
    @Bindable var node: MIDIInputNode

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Text("MIDI Input")
                .font(.system(size: 10))
                .bold()

            HStack
            {
                Text("Input:")
                    .font(.system(size: 10))

                Picker("", selection: $node.selectedInputID)
                {
                    Text("None").tag(String?.none)

                    ForEach(node.availableInputs) { input in
                        Text(input.displayName).tag(Optional(input.id))
                    }
                }
                .pickerStyle(.menu)

                Button("Refresh")
                {
                    node.refreshInputs()
                }
                .controlSize(.small)
            }

            Divider()

            Text("MIDI Bindings:")
                .font(.system(size: 10))

            ScrollView
            {
                VStack(alignment: .leading, spacing: 4)
                {
                    ForEach(node.midiBindings) { binding in
                        MIDIBindingConfigView(node: node, bindingID: binding.id)
                    }
                }
            }
            .frame(maxHeight: 120)

            HStack
            {
                Spacer()

                Button("+")
                {
                    node.addBinding()
                }
                .controlSize(.small)

                Spacer()
            }

            Spacer()
        }
        .padding(4)
    }
}

// MARK: - MIDI Input Node

@Observable public class MIDIInputNode: Node
{
    override public static var name: String { "MIDI Input" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .IO) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Receive MIDI messages from external devices" }

    // Dynamic node name based on selected input
    override public var name: String
    {
        if let inputID = selectedInputID,
           let input = availableInputs.first(where: { $0.id == inputID })
        {
            return input.name
        }
        return Self.name
    }

    // MARK: - Codable

    private enum MIDICodingKeys: String, CodingKey
    {
        case selectedInputID
        case savedInputInfo
        case midiBindings
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: MIDICodingKeys.self)

        self.selectedInputID = try container.decodeIfPresent(String.self, forKey: .selectedInputID)
        self.savedInputInfo = try container.decodeIfPresent(MIDIInputInfo.self, forKey: .savedInputInfo)
        self.midiBindings = try container.decodeIfPresent([MIDIBinding].self, forKey: .midiBindings) ?? []

        rebuildPorts()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: MIDICodingKeys.self)
        try container.encodeIfPresent(self.selectedInputID, forKey: .selectedInputID)

        if let inputID = selectedInputID,
           let info = availableInputs.first(where: { $0.id == inputID })
        {
            try container.encode(info, forKey: .savedInputInfo)
        }

        try container.encode(self.midiBindings, forKey: .midiBindings)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    // MARK: - Properties

    @ObservationIgnored private var midiManager: MIDIManager?
    @ObservationIgnored private var savedInputInfo: MIDIInputInfo?

    @ObservationIgnored fileprivate var selectedInputID: String?
    {
        didSet
        {
            setupMIDIConnection()
        }
    }

    @ObservationIgnored fileprivate var availableInputs: [MIDIInputInfo] = []

    @ObservationIgnored fileprivate var midiBindings: [MIDIBinding] = []
    {
        didSet
        {
            rebuildPorts()
        }
    }

    // Latest values
    @ObservationIgnored private var floatValues: [UUID: Float] = [:]
    @ObservationIgnored private var boolValues: [UUID: Bool] = [:]

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool
    {
        true
    }

    override public func settingsView() -> AnyView
    {
        AnyView(MIDIInputNodeView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Medium }

    // MARK: - Lifecycle

    public override func enableExecution(context: GraphExecutionContext)
    {
        setupMIDIManager()
    }

    public override func disableExecution(context: GraphExecutionContext)
    {
        midiManager = nil
    }

    private func setupMIDIManager()
    {
        do
        {
            midiManager = MIDIManager(
                clientName: "Fabric",
                model: "Fabric",
                manufacturer: "Fabric"
            )

            try midiManager?.start()
            print("[MIDI] Manager started")

            refreshInputs()

            // Try to reconnect to saved input
            if let savedInfo = savedInputInfo,
               let matching = availableInputs.first(where: { $0.name == savedInfo.name })
            {
                selectedInputID = matching.id
            }
        }
        catch
        {
            print("[MIDI] Failed to start manager: \(error)")
        }
    }

    fileprivate func refreshInputs()
    {
        guard let manager = midiManager else { return }

        // List output endpoints - these are devices that SEND MIDI data (controllers, keyboards, etc.)
        availableInputs = manager.endpoints.outputs.map { endpoint in
            MIDIInputInfo(
                id: endpoint.uniqueID.description,
                name: endpoint.displayName,
                manufacturer: endpoint.manufacturer
            )
        }

        print("[MIDI] Found \(availableInputs.count) MIDI sources:")
        for input in availableInputs
        {
            print("  - \(input.displayName)")
        }
    }

    private func setupMIDIConnection()
    {
        guard let manager = midiManager else { return }

        guard
              let inputID = selectedInputID,
              let endpoint = manager.endpoints.outputs.first(where: { $0.uniqueID.description == inputID })
        else
        {
            // Remove existing connection if any
            manager.remove(.inputConnection, .all)
            return
        }

        do
        {
            // Remove existing connections
            manager.remove(.inputConnection, .all)

            // Create new connection to receive from this output endpoint
            try manager.addInputConnection(
                to: .outputs([endpoint]),
                tag: "FabricMIDI",
                receiver: .events { [weak self] events, _, _ in
                    self?.handleMIDIEvents(events)
                }
            )

            print("[MIDI] Connected to: \(endpoint.displayName)")
        }
        catch
        {
            print("[MIDI] Failed to connect: \(error)")
        }
    }

    private func handleMIDIEvents(_ events: [MIDIEvent])
    {
        for event in events
        {
            switch event
            {
            case .noteOn(let payload):
                handleNoteOn(channel: Int(payload.channel.intValue), note: Int(payload.note.number.intValue), velocity: Int(payload.velocity.midi1Value.intValue))

            case .noteOff(let payload):
                handleNoteOff(channel: Int(payload.channel.intValue), note: Int(payload.note.number.intValue))

            case .cc(let payload):
                handleCC(channel: Int(payload.channel.intValue), cc: Int(payload.controller.number.intValue), value: Int(payload.value.midi1Value.intValue))

            case .pitchBend(let payload):
                handlePitchBend(channel: Int(payload.channel.intValue), value: payload.value.bipolarUnitIntervalValue)

            case .pressure(let payload):
                handleAftertouch(channel: Int(payload.channel.intValue), value: Int(payload.amount.midi1Value.intValue))

            default:
                break
            }
        }
    }

    private func handleNoteOn(channel: Int, note: Int, velocity: Int)
    {
        for binding in midiBindings
        {
            guard binding.number == note else { continue }
            guard binding.channel == 0 || binding.channel == channel + 1 else { continue }

            switch binding.type
            {
            case .noteGate:
                boolValues[binding.id] = true
            case .noteVelocity:
                floatValues[binding.id] = Float(velocity) / 127.0
            default:
                break
            }
        }
        markDirty()
    }

    private func handleNoteOff(channel: Int, note: Int)
    {
        for binding in midiBindings
        {
            guard binding.number == note else { continue }
            guard binding.channel == 0 || binding.channel == channel + 1 else { continue }

            switch binding.type
            {
            case .noteGate:
                boolValues[binding.id] = false
            case .noteVelocity:
                floatValues[binding.id] = 0.0
            default:
                break
            }
        }
        markDirty()
    }

    private func handleCC(channel: Int, cc: Int, value: Int)
    {
        for binding in midiBindings
        {
            guard binding.type == .controlChange else { continue }
            guard binding.number == cc else { continue }
            guard binding.channel == 0 || binding.channel == channel + 1 else { continue }

            floatValues[binding.id] = Float(value) / 127.0
        }
        markDirty()
    }

    private func handlePitchBend(channel: Int, value: Double)
    {
        for binding in midiBindings
        {
            guard binding.type == .pitchBend else { continue }
            guard binding.channel == 0 || binding.channel == channel + 1 else { continue }

            // Convert from -1...1 to 0...1
            floatValues[binding.id] = Float((value + 1.0) / 2.0)
        }
        markDirty()
    }

    private func handleAftertouch(channel: Int, value: Int)
    {
        for binding in midiBindings
        {
            guard binding.type == .aftertouch else { continue }
            guard binding.channel == 0 || binding.channel == channel + 1 else { continue }

            floatValues[binding.id] = Float(value) / 127.0
        }
        markDirty()
    }

    // MARK: - Binding Management

    fileprivate func addBinding()
    {
        let binding = MIDIBinding(type: .controlChange, channel: 0, number: midiBindings.count + 1)
        midiBindings.append(binding)
    }

    fileprivate func removeBinding(id: UUID)
    {
        midiBindings.removeAll(where: { $0.id == id })
    }

    // MARK: - Port Management

    private func rebuildPorts()
    {
        let portNamesWeNeed = Set(midiBindings.map { portNameForBinding($0) })
        let existingPortNames = Set(outputPorts().map { $0.name })

        let portsToRemove = existingPortNames.subtracting(portNamesWeNeed)

        for portName in portsToRemove
        {
            if let port = findPort(named: portName)
            {
                removePort(port)
            }
        }

        for binding in midiBindings
        {
            let portName = portNameForBinding(binding)

            if findPort(named: portName) != nil
            {
                continue
            }

            let port: Port
            if binding.type == .noteGate
            {
                port = NodePort<Bool>(name: portName, kind: .Outlet)
                boolValues[binding.id] = false
            }
            else
            {
                port = NodePort<Float>(name: portName, kind: .Outlet)
                floatValues[binding.id] = 0.0
            }

            addDynamicPort(port)
            print("[MIDI] Added port: \(portName)")
        }
    }

    private func portNameForBinding(_ binding: MIDIBinding) -> String
    {
        return binding.displayName
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        for binding in midiBindings
        {
            let portName = portNameForBinding(binding)

            if binding.type == .noteGate
            {
                if let port = findPort(named: portName) as? NodePort<Bool>,
                   let value = boolValues[binding.id]
                {
                    port.send(value)
                }
            }
            else
            {
                if let port = findPort(named: portName) as? NodePort<Float>,
                   let value = floatValues[binding.id]
                {
                    port.send(value)
                }
            }
        }
    }
}
