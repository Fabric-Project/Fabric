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
public struct KeyBinding: Codable, Equatable
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

    @Bindable var node:KeyboardNode
    let keypressIndex:Int

     var body: some View {

         let keyBinding:KeyBinding? = self.node.keyBindings[self.keypressIndex]

         HStack {

             Button("Bind key \(self.keypressIndex + 1)") {
                 self.focused = true
             }
             .controlSize(.small)

             Text("\(keyBinding?.modifiersDescription ?? "Bind a key: ")  \(keyBinding?.keyDescription ?? "")")
                 .focusable()
                 .focused($focused)

                 .onKeyPress(phases: .down) { press in
                     self.node.keyBindings[self.keypressIndex] = KeyBinding(from: press)
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
    @Bindable var node:KeyboardNode

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text("Configure Keyboard Output")
                .lineLimit(1)
                .font(.system(size: 10))

            ForEach( 0 ..< self.node.keyBindings.count, id:\.self ) { keyPressIdx in

                KeyboardKeyConfigView(node:node, keypressIndex: keyPressIdx)
            }

            Spacer()

            HStack
            {
                Spacer()

                Button("-") {
                    if self.node.keyBindings.isEmpty { return }

                    self.node.keyBindings.removeLast()
                }

                Spacer()

                Button("+") {
                    self.node.keyBindings.append(nil)
                }

                Spacer()
            }
        }
    }
}

@Observable public class KeyboardNode : Node
{
    override public class var name:String { "Keyboard" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Configure and detect keypresses"}

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

        // Use decoded bindings or default to [nil]
        self.keyBindings = decodedBindings ?? [nil]

        // Rebuild ports based on restored bindings
        self.rebuildPorts()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: KeyboardCodingKeys.self)
        try container.encode(self.keyBindings, forKey: .keyBindings)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    // MARK: - Execution

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let eventInfo = context.eventInfo,
           let event = eventInfo.event,
           ( event.type == .keyDown || event.type == .keyUp ),
            let characters = event.characters
        {
            for keyBinding in keyBindings {
                if let keyBinding,
                   let portName = self.portNameForKeyBinding(keyBinding),
                   let port = self.findPort(named: portName) as? NodePort<Bool>
                {
                    if characters == keyBinding.characters
                    {
                        if event.type == .keyDown
                        {
                            port.send(true)
                        }
                        else
                        {
                            port.send(false)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Properties

    fileprivate var keyBindings:[KeyBinding?] = [nil]
    {
        didSet
        {
            self.rebuildPorts()
        }
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool {
        true
    }

    override public func settingsView() -> AnyView
    {
        AnyView(KeyboardNodeView(node: self))
    }

    // MARK: - Internal Funcs

    private func rebuildPorts()
    {
        let portNamesWeNeed = self.keyBindings.compactMap{ self.portNameForKeyBinding($0) }
        let existingPortNames = self.outputPorts().map { $0.name }

        let portsNamesToRemove = Set(existingPortNames).subtracting(Set(portNamesWeNeed))
        let portNamesToAdd = Set(portNamesWeNeed).subtracting(portsNamesToRemove)

        for portName in portsNamesToRemove
        {
            if let port = self.findPort(named: portName) as? NodePort<Bool>
            {
                self.removePort(port)
            }
        }

        for portName in portNamesToAdd
        {
            if self.findPort(named: portName) == nil
            {
                let port = NodePort<Bool>(name: portName, kind: .Outlet, description: "True when key '\(portName)' is pressed")

                self.addDynamicPort(port)
                print("add port \(portName) ")
            }
        }
    }

    private func portNameForKeyBinding(_ keyBinding:KeyBinding?) -> String?
    {
        guard let keyBinding else { return nil }

        return keyBinding.characters
    }
}

#endif // os(macOS)
