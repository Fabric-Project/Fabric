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

// MARK: - Detected MIDI Input

/// Represents a detected MIDI input during learn mode
public struct DetectedMIDIInput: Codable, Equatable, Identifiable, Hashable
{
    public let id: UUID
    public var type: DetectedMIDIType
    public var channel: Int // 0-15 (MIDI channel)
    public var number: Int  // Note number or CC number (0-127)
    public var currentValue: Float // Last detected value (normalized 0-1)

    public init(type: DetectedMIDIType, channel: Int, number: Int, value: Float = 0)
    {
        self.id = UUID()
        self.type = type
        self.channel = channel
        self.number = number
        self.currentValue = value
    }

    public var portName: String
    {
        let channelStr = "Ch\(channel + 1)"
        switch type
        {
        case .noteGate:
            return "\(channelStr) Note \(number) Gate"
        case .noteVelocity:
            return "\(channelStr) Note \(number) Vel"
        case .controlChange:
            return "\(channelStr) CC \(number)"
        case .pitchBend:
            return "\(channelStr) Pitch Bend"
        case .aftertouch:
            return "\(channelStr) Aftertouch"
        }
    }

    /// Unique key for deduplication (same type+channel+number = same control)
    public var uniqueKey: String
    {
        switch type
        {
        case .noteGate, .noteVelocity:
            return "\(type.rawValue)-\(channel)-\(number)"
        case .controlChange:
            return "cc-\(channel)-\(number)"
        case .pitchBend:
            return "pb-\(channel)"
        case .aftertouch:
            return "at-\(channel)"
        }
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(uniqueKey)
    }

    public static func == (lhs: DetectedMIDIInput, rhs: DetectedMIDIInput) -> Bool
    {
        lhs.uniqueKey == rhs.uniqueKey
    }
}

public enum DetectedMIDIType: String, Codable, CaseIterable
{
    case noteGate = "Note Gate"
    case noteVelocity = "Note Velocity"
    case controlChange = "CC"
    case pitchBend = "Pitch Bend"
    case aftertouch = "Aftertouch"
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

            // Device selection
            HStack
            {
                Text("Device:")
                    .font(.system(size: 10))

                Picker("", selection: $node.selectedInputID)
                {
                    Text("None").tag(String?.none)

                    ForEach(node.availableInputs) { input in
                        Text(input.displayName).tag(Optional(input.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(node.isListening)

                Button("Refresh")
                {
                    node.refreshInputs()
                }
                .controlSize(.small)
                .disabled(node.isListening)
            }

            Divider()

            // Learn mode controls
            HStack
            {
                if node.isListening
                {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)

                    Text("Listening...")
                        .font(.system(size: 10))
                        .foregroundColor(.red)

                    Spacer()

                    Button("Stop")
                    {
                        node.stopListening()
                    }
                    .controlSize(.small)

                    Button("Clear")
                    {
                        node.clearDetected()
                    }
                    .controlSize(.small)
                }
                else
                {
                    Text("Learn Mode")
                        .font(.system(size: 10))

                    Spacer()

                    Button("Listen")
                    {
                        node.startListening()
                    }
                    .controlSize(.small)
                    .disabled(node.selectedInputID == nil)
                }
            }

            // Detected inputs during learn mode OR configured ports
            if node.isListening
            {
                ScrollView
                {
                    VStack(alignment: .leading, spacing: 2)
                    {
                        if node.detectedInputs.isEmpty
                        {
                            Text("Move controls on your MIDI device...")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        else
                        {
                            ForEach(Array(node.detectedInputs.sorted(by: { $0.portName < $1.portName }))) { input in
                                DetectedInputRow(input: input)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            else if !node.configuredInputs.isEmpty
            {
                Text("Configured Ports:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                ScrollView
                {
                    VStack(alignment: .leading, spacing: 2)
                    {
                        ForEach(node.configuredInputs) { input in
                            HStack
                            {
                                Text(input.portName)
                                    .font(.system(size: 9, design: .monospaced))

                                Spacer()

                                Button(action: {
                                    node.removeConfiguredInput(id: input.id)
                                }) {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)

                HStack
                {
                    Spacer()
                    Button("Clear All")
                    {
                        node.clearConfigured()
                    }
                    .controlSize(.small)
                }
            }
            else
            {
                Text("No MIDI inputs configured.\nSelect a device and click Listen.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(4)
    }
}

struct DetectedInputRow: View
{
    let input: DetectedMIDIInput

    var body: some View
    {
        HStack
        {
            Text(input.portName)
                .font(.system(size: 9, design: .monospaced))

            Spacer()

            // Value indicator
            GeometryReader { geo in
                ZStack(alignment: .leading)
                {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))

                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(input.currentValue))
                }
            }
            .frame(width: 40, height: 8)
            .cornerRadius(2)

            Text(String(format: "%.0f", input.currentValue * 127))
                .font(.system(size: 8, design: .monospaced))
                .frame(width: 24, alignment: .trailing)
        }
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
        case configuredInputs
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: MIDICodingKeys.self)

        self.selectedInputID = try container.decodeIfPresent(String.self, forKey: .selectedInputID)
        self.savedInputInfo = try container.decodeIfPresent(MIDIInputInfo.self, forKey: .savedInputInfo)
        self.configuredInputs = try container.decodeIfPresent([DetectedMIDIInput].self, forKey: .configuredInputs) ?? []

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

        try container.encode(self.configuredInputs, forKey: .configuredInputs)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    // MARK: - Properties

    @ObservationIgnored private var midiManager: MIDIManager?
    @ObservationIgnored private var savedInputInfo: MIDIInputInfo?

    // UI-bound properties (must NOT be @ObservationIgnored for SwiftUI updates)
    fileprivate var selectedInputID: String?
    {
        didSet
        {
            setupMIDIConnection()
        }
    }

    fileprivate var availableInputs: [MIDIInputInfo] = []

    // Learn mode state
    fileprivate var isListening: Bool = false
    fileprivate var detectedInputs: Set<DetectedMIDIInput> = []

    // Configured inputs (after learning)
    fileprivate var configuredInputs: [DetectedMIDIInput] = []
    {
        didSet
        {
            rebuildPorts()
        }
    }

    // Latest values for execution (these don't need UI observation)
    @ObservationIgnored private var floatValues: [String: Float] = [:]
    @ObservationIgnored private var boolValues: [String: Bool] = [:]

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

    // MARK: - Learn Mode

    fileprivate func startListening()
    {
        print("[MIDI] Learn mode starting... isListening was \(isListening)")
        isListening = true
        detectedInputs.removeAll()
        print("[MIDI] Learn mode started. isListening is now \(isListening)")
    }

    fileprivate func stopListening()
    {
        print("[MIDI] Stopping learn mode. Detected \(detectedInputs.count) inputs")
        isListening = false

        // Convert detected inputs to configured inputs
        for detected in detectedInputs
        {
            print("[MIDI] Processing detected: \(detected.portName)")
            // Skip if we already have this input configured
            if !configuredInputs.contains(where: { $0.uniqueKey == detected.uniqueKey })
            {
                configuredInputs.append(detected)
                print("[MIDI] Added to configured: \(detected.portName)")
            }
            else
            {
                print("[MIDI] Already configured: \(detected.portName)")
            }
        }

        detectedInputs.removeAll()
        print("[MIDI] Learn mode stopped. Total configured: \(configuredInputs.count) inputs. isListening is now \(isListening)")
    }

    fileprivate func clearDetected()
    {
        detectedInputs.removeAll()
    }

    fileprivate func clearConfigured()
    {
        configuredInputs.removeAll()
    }

    fileprivate func removeConfiguredInput(id: UUID)
    {
        configuredInputs.removeAll(where: { $0.id == id })
    }

    // MARK: - MIDI Event Handling

    private func handleMIDIEvents(_ events: [MIDIEvent])
    {
        for event in events
        {
            switch event
            {
            case .noteOn(let payload):
                handleNoteOn(
                    channel: Int(payload.channel.intValue),
                    note: Int(payload.note.number.intValue),
                    velocity: Int(payload.velocity.midi1Value.intValue)
                )

            case .noteOff(let payload):
                handleNoteOff(
                    channel: Int(payload.channel.intValue),
                    note: Int(payload.note.number.intValue)
                )

            case .cc(let payload):
                handleCC(
                    channel: Int(payload.channel.intValue),
                    cc: Int(payload.controller.number.intValue),
                    value: Int(payload.value.midi1Value.intValue)
                )

            case .pitchBend(let payload):
                handlePitchBend(
                    channel: Int(payload.channel.intValue),
                    value: payload.value.bipolarUnitIntervalValue
                )

            case .pressure(let payload):
                handleAftertouch(
                    channel: Int(payload.channel.intValue),
                    value: Int(payload.amount.midi1Value.intValue)
                )

            default:
                break
            }
        }
    }

    private func handleNoteOn(channel: Int, note: Int, velocity: Int)
    {
        let normalizedVel = Float(velocity) / 127.0
        print("[MIDI] Note On: ch=\(channel + 1) note=\(note) vel=\(velocity)")

        if isListening
        {
            // Add both gate and velocity for notes
            let gateInput = DetectedMIDIInput(type: .noteGate, channel: channel, number: note, value: 1.0)
            let velInput = DetectedMIDIInput(type: .noteVelocity, channel: channel, number: note, value: normalizedVel)

            // Update existing or insert new (Set replaces by uniqueKey due to Hashable impl)
            if let existing = detectedInputs.first(where: { $0.uniqueKey == gateInput.uniqueKey })
            {
                detectedInputs.remove(existing)
            }
            detectedInputs.insert(gateInput)
            print("[MIDI] Detected: \(gateInput.portName)")

            if let existing = detectedInputs.first(where: { $0.uniqueKey == velInput.uniqueKey })
            {
                detectedInputs.remove(existing)
            }
            detectedInputs.insert(velInput)
            print("[MIDI] Detected: \(velInput.portName)")
        }

        // Update values for configured inputs
        for input in configuredInputs
        {
            if input.channel == channel && input.number == note
            {
                switch input.type
                {
                case .noteGate:
                    boolValues[input.uniqueKey] = true
                case .noteVelocity:
                    floatValues[input.uniqueKey] = normalizedVel
                default:
                    break
                }
            }
        }
        markDirty()
    }

    private func handleNoteOff(channel: Int, note: Int)
    {
        if isListening
        {
            // Update gate to show off state
            let gateInput = DetectedMIDIInput(type: .noteGate, channel: channel, number: note, value: 0.0)
            if let existing = detectedInputs.first(where: { $0.uniqueKey == gateInput.uniqueKey })
            {
                detectedInputs.remove(existing)
                let updated = DetectedMIDIInput(type: existing.type, channel: existing.channel, number: existing.number, value: 0.0)
                detectedInputs.insert(updated)
            }
        }

        // Update values for configured inputs
        for input in configuredInputs
        {
            if input.channel == channel && input.number == note
            {
                switch input.type
                {
                case .noteGate:
                    boolValues[input.uniqueKey] = false
                case .noteVelocity:
                    floatValues[input.uniqueKey] = 0.0
                default:
                    break
                }
            }
        }
        markDirty()
    }

    private func handleCC(channel: Int, cc: Int, value: Int)
    {
        let normalizedValue = Float(value) / 127.0
        print("[MIDI] CC: ch=\(channel + 1) cc=\(cc) val=\(value)")

        if isListening
        {
            let ccInput = DetectedMIDIInput(type: .controlChange, channel: channel, number: cc, value: normalizedValue)

            if let existing = detectedInputs.first(where: { $0.uniqueKey == ccInput.uniqueKey })
            {
                detectedInputs.remove(existing)
            }
            detectedInputs.insert(ccInput)
            print("[MIDI] Detected: \(ccInput.portName) = \(normalizedValue)")
        }

        // Update values for configured inputs
        for input in configuredInputs
        {
            if input.type == .controlChange && input.channel == channel && input.number == cc
            {
                floatValues[input.uniqueKey] = normalizedValue
            }
        }
        markDirty()
    }

    private func handlePitchBend(channel: Int, value: Double)
    {
        // Convert from -1...1 to 0...1
        let normalizedValue = Float((value + 1.0) / 2.0)
        print("[MIDI] Pitch Bend: ch=\(channel + 1) val=\(value)")

        if isListening
        {
            let pbInput = DetectedMIDIInput(type: .pitchBend, channel: channel, number: 0, value: normalizedValue)

            if let existing = detectedInputs.first(where: { $0.uniqueKey == pbInput.uniqueKey })
            {
                detectedInputs.remove(existing)
            }
            detectedInputs.insert(pbInput)
            print("[MIDI] Detected: \(pbInput.portName)")
        }

        // Update values for configured inputs
        for input in configuredInputs
        {
            if input.type == .pitchBend && input.channel == channel
            {
                floatValues[input.uniqueKey] = normalizedValue
            }
        }
        markDirty()
    }

    private func handleAftertouch(channel: Int, value: Int)
    {
        let normalizedValue = Float(value) / 127.0
        print("[MIDI] Aftertouch: ch=\(channel + 1) val=\(value)")

        if isListening
        {
            let atInput = DetectedMIDIInput(type: .aftertouch, channel: channel, number: 0, value: normalizedValue)

            if let existing = detectedInputs.first(where: { $0.uniqueKey == atInput.uniqueKey })
            {
                detectedInputs.remove(existing)
            }
            detectedInputs.insert(atInput)
            print("[MIDI] Detected: \(atInput.portName)")
        }

        // Update values for configured inputs
        for input in configuredInputs
        {
            if input.type == .aftertouch && input.channel == channel
            {
                floatValues[input.uniqueKey] = normalizedValue
            }
        }
        markDirty()
    }

    // MARK: - Port Management

    private func rebuildPorts()
    {
        let portNamesWeNeed = Set(configuredInputs.map { $0.portName })
        let existingPortNames = Set(outputPorts().map { $0.name })

        let portsToRemove = existingPortNames.subtracting(portNamesWeNeed)

        for portName in portsToRemove
        {
            if let port = findPort(named: portName)
            {
                removePort(port)
            }
        }

        for input in configuredInputs
        {
            let portName = input.portName

            if findPort(named: portName) != nil
            {
                continue
            }

            let port: Port
            if input.type == .noteGate
            {
                port = NodePort<Bool>(name: portName, kind: .Outlet, description: "MIDI note gate (true while note is held)")
                boolValues[input.uniqueKey] = false
            }
            else
            {
                port = NodePort<Float>(name: portName, kind: .Outlet, description: "MIDI value normalized from 0 to 1")
                floatValues[input.uniqueKey] = 0.0
            }

            addDynamicPort(port)
            print("[MIDI] Added port: \(portName)")
        }
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        for input in configuredInputs
        {
            let portName = input.portName

            if input.type == .noteGate
            {
                if let port = findPort(named: portName) as? NodePort<Bool>,
                   let value = boolValues[input.uniqueKey]
                {
                    port.send(value)
                }
            }
            else
            {
                if let port = findPort(named: portName) as? NodePort<Float>,
                   let value = floatValues[input.uniqueKey]
                {
                    port.send(value)
                }
            }
        }
    }
}
