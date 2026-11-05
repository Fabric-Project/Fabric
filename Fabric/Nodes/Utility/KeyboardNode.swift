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
        // Decoded before super.init, which declares a port per binding.
        let container = try decoder.container(keyedBy: KeyboardCodingKeys.self)
        self.keyBindings = try container.decodeIfPresent([KeyBinding?].self, forKey: .keyBindings) ?? [nil]

        try super.init(from: decoder)
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
        self.init(context: context, settings: KeyboardSettings(keyBindings: keyBindings.map { Optional($0) }))
    }

    public convenience init(context: Context, settings: KeyboardSettings)
    {
        self.init(context: context)
        self.apply(settings)
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
            for (bindingCharacters, port) in keyOutlets where characters == bindingCharacters
            {
                port.send(event.type == .keyDown)
            }
        }
    }

    // MARK: - Properties

    fileprivate var keyBindings: [KeyBinding?] = [nil]
    {
        didSet
        {
            self.reconcilePorts()
            self.settingsDidChange()
        }
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        AnyView(KeyboardNodeView(model: settingsModel))
    }

    // MARK: - Settings Model

    @MainActor
    @Observable final class SettingsModel
    {
        var keyBindings: [KeyBinding?]
        {
            didSet
            {
                guard keyBindings != node?.keyBindings else { return }
                node?.setSettings(KeyboardSettings(keyBindings: keyBindings))
            }
        }
        private weak var node: KeyboardNode?

        init(node: KeyboardNode)
        {
            self.node = node
            self.keyBindings = node.keyBindings
        }

        func refreshFromNode()
        {
            guard let node, keyBindings != node.keyBindings else { return }
            keyBindings = node.keyBindings
        }
    }

    private var settingsModel: SettingsModel
    {
        performOnMainSync
        {
            if let model = _settingsModelStorage { return model }
            let model = SettingsModel(node: self)
            _settingsModelStorage = model
            return model
        }
    }

    /// Nil until a settings view asks for it.
    private var _settingsModelStorage: SettingsModel?

    override public func refreshSettingsModel()
    {
        super.refreshSettingsModel()
        _settingsModelStorage?.refreshFromNode()
    }

    // MARK: - Internal

    /// Each bound key's characters and outlet, in binding order.
    private var keyOutlets: [(characters: String, port: NodePort<Bool>)] = []

    override public func bindPorts()
    {
        super.bindPorts()
        self.keyOutlets = keyBindings.compactMap { binding in
            guard let binding, let portName = portNameForKeyBinding(binding),
                  let port: NodePort<Bool> = findPort(named: portName)
            else { return nil }
            return (binding.characters, port)
        }
    }

    /// A Bool outlet per bound key, in binding order.
    override public func declaredPorts() -> [PortDeclaration]
    {
        super.declaredPorts() + self.keyBindings.compactMap { self.portNameForKeyBinding($0) }.map { portName in
            PortDeclaration(key: portName,
                            port: NodePort<Bool>(name: portName, kind: .Outlet,
                                                 description: "True when key '\(portName)' is pressed"))
        }
    }

    private func portNameForKeyBinding(_ keyBinding: KeyBinding?) -> String?
    {
        guard let keyBinding else { return nil }
        return keyBinding.characters
    }
}

#endif // os(macOS)
