//
//  KeyboardNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/10/25.
//

#if os(macOS)

import SwiftUI
import Satin
import simd
import Metal

extension KeyEquivalent
{
    public var description: String
    {
        return String(self.character)
    }
}

extension EventModifiers : @retroactive Sequence
{

}

extension EventModifiers
{
    public var description: String
    {
        switch self
        {
        case .capsLock: return "􀆡 &"
        case .command: return "⌘ &"
        case .control: return "⌃ &"
        case .option: return "⌥ &"
        case .shift: return "⇧ &"
        default:
            return ""
        }
    }

    public var completeDescription: String
    {
        var string = ""
        for modifier in self
        {
            string += " " + modifier.description
        }

        return string
    }
}

// MARK: - Codable Key Binding

/// A Codable representation of a key binding since KeyPress is not Codable
public struct KeyBinding: Codable, Equatable, Sendable
{
    public let characters: String
    public let keyDescription: String
    public let modifiersDescription: String

    public init(from keyPress: KeyPress)
    {
        self.characters = keyPress.characters
        self.keyDescription = keyPress.key.description
        self.modifiersDescription = keyPress.modifiers.completeDescription
    }

    public init(characters: String, keyDescription: String, modifiersDescription: String)
    {
        self.characters = characters
        self.keyDescription = keyDescription
        self.modifiersDescription = modifiersDescription
    }
}

struct KeyboardKeyConfigView : View
{
    @FocusState private var focused: Bool

    @Bindable var model: KeyboardNode.SettingsModel
    let keypressIndex: Int

    var body: some View
    {
        let keyBinding: KeyBinding? = model.keyBindings[keypressIndex]

        HStack {
            Button("Bind key \(keypressIndex + 1)") {
                focused = true
            }
            .controlSize(.small)

            Text("\(keyBinding?.modifiersDescription ?? "Bind a key: ")  \(keyBinding?.keyDescription ?? "")")
                .focusable()
                .focused($focused)
                .onKeyPress(phases: .down) { press in
                    model.keyBindings[keypressIndex] = KeyBinding(from: press)
                    return .handled
                }
                .lineLimit(1)
                .font(.system(size: 10))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct KeyboardNodeView : View
{
    @Bindable var model: KeyboardNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("Configure Keyboard Output")
                .lineLimit(1)
                .font(.system(size: 10))

            ForEach(0 ..< model.keyBindings.count, id: \.self) { keyPressIdx in
                KeyboardKeyConfigView(model: model, keypressIndex: keyPressIdx)
            }

            Spacer()

            HStack
            {
                Spacer()

                Button("-") {
                    if model.keyBindings.isEmpty { return }
                    model.keyBindings.removeLast()
                }

                Spacer()

                Button("+") {
                    model.keyBindings.append(nil)
                }

                Spacer()
            }
        }
    }
}

/// The settings of a Keyboard node: its key bindings, one output each. A
/// slot not yet bound is nil.
public struct KeyboardSettings: NodeSettings
{
    public var keyBindings: [KeyBinding?]

    public init(keyBindings: [KeyBinding?])
    {
        self.keyBindings = keyBindings
    }
}

public class KeyboardNode : Node
{
    override public class var name: String { "Keyboard" }
    override public class var nodeType: Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Configure and detect keypresses" }

    // MARK: - Codable

    private enum KeyboardCodingKeys: String, CodingKey
    {
        case keyBindings
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: KeyboardCodingKeys.self)
        let decodedBindings = try container.decodeIfPresent([KeyBinding?].self, forKey: .keyBindings)

        self.keyBindings = decodedBindings ?? [nil]
        self.rebuildPorts()
    }

    override public var settings: (any NodeSettings)? { KeyboardSettings(keyBindings: keyBindings) }

    override public func apply(_ settings: any NodeSettings)
    {
        guard let settings = settings as? KeyboardSettings else { return }
        if settings.keyBindings != keyBindings { keyBindings = settings.keyBindings }
        super.apply(settings)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    public convenience init(context: Context, keyBindings: [KeyBinding])
    {
        self.init(context: context)
        self.keyBindings = keyBindings.map { Optional($0) }
        self.rebuildPorts()
    }

    public convenience init(context: Context, settings: KeyboardSettings)
    {
        self.init(context: context)
        self.keyBindings = settings.keyBindings
        self.rebuildPorts()
    }

    // MARK: - Execution

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if let eventInfo = executionInfo.eventInfo,
           let event = eventInfo.event,
           (event.type == .keyDown || event.type == .keyUp),
           let characters = event.characters
        {
            for keyBinding in keyBindings
            {
                if let keyBinding,
                   let portName = self.portNameForKeyBinding(keyBinding),
                   let port = self.findPort(named: portName) as? NodePort<Bool>
                {
                    if characters == keyBinding.characters
                    {
                        port.send(event.type == .keyDown)
                    }
                }
            }
        }
    }

    // MARK: - Properties

    fileprivate private(set) var keyBindings: [KeyBinding?] = [nil]
    {
        didSet
        {
            self.rebuildPorts()
        }
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        AnyView(KeyboardNodeView(model: _settingsModel))
    }

    // MARK: - Settings Model

    /// Each binding made, added or removed is committed as it is made.
    @MainActor
    @Observable final class SettingsModel
    {
        let draft: NodeSettingsDraft<KeyboardSettings>

        var keyBindings: [KeyBinding?]
        {
            get { draft.value.keyBindings }
            set { draft.value.keyBindings = newValue }
        }

        init(node: KeyboardNode)
        {
            self.draft = NodeSettingsDraft(of: KeyboardSettings(keyBindings: node.keyBindings), on: node, commit: .eachChange)
        }
    }

    // Made for the settings view, on the main thread.
    private lazy var _settingsModel: SettingsModel = MainActor.assumeIsolated { SettingsModel(node: self) }

    // MARK: - Internal

    private func rebuildPorts()
    {
        self.reconcilePorts()
    }

    /// A Bool outlet for each bound key, in binding order.
    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + self.keyBindings.compactMap { self.portNameForKeyBinding($0) }.map { portName in
            PortDeclaration(registryKey: portName,
                            port: NodePort<Bool>(name: portName, kind: .Outlet, description: "True when key '\(portName)' is pressed"))
        }
    }

    private func portNameForKeyBinding(_ keyBinding: KeyBinding?) -> String?
    {
        guard let keyBinding else { return nil }
        return keyBinding.characters
    }
}

#endif // os(macOS)
