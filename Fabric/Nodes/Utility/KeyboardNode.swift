//
//  LogNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/10/25.
//


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

struct KeyboardKeyConfigView : View
{
    @FocusState private var focused: Bool

    @Bindable var node:KeyboardNode
    let keypressIndex:Int
    
     var body: some View {
         
         let keyPress:KeyPress? = self.node.keyPresses[self.keypressIndex]
         
         HStack {
             
             Button("Bind key \(self.keypressIndex + 1)") {
                 self.focused = true
             }
             .controlSize(.small)
             
             Text("\(keyPress?.modifiers.completeDescription ?? "Bind a key: ")  \(keyPress?.key.description ?? "")")
                 .focusable()
                 .focused($focused)
             
                 .onKeyPress(phases: .down) { press in
                     self.node.keyPresses[self.keypressIndex] = press
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

            ForEach( 0 ..< self.node.keyPresses.count, id:\.self ) { keyPressIdx in
                
                KeyboardKeyConfigView(node:node, keypressIndex: keyPressIdx)
            }
            
            Spacer()
            
            HStack
            {
                Spacer()

                Button("-") {
                    if self.node.keyPresses.isEmpty { return }
                    
                    self.node.keyPresses.removeLast()
                }
                
                Spacer()

                Button("+") {
                    self.node.keyPresses.append(nil)
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

    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let eventInfo = context.eventInfo,
           let event = eventInfo.event,
           ( event.type == .keyDown || event.type == .keyUp ),
            let characters = event.characters
        {
            for keyPress in keyPresses {
                if let keyPress,
                   let portName = self.portNameForKeyPress(keyPress),
                   let port = self.findPort(named: portName) as? NodePort<Bool>
                {
                    if characters == keyPress.characters
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
    
    fileprivate var keyPresses:[KeyPress?] = [nil] 
    {
        didSet
        {
            self.rebuildPorts()
        }
    }

    // Settings View
    override public func providesSettingsView() -> Bool {
        true
    }
    
    override public func settingsView() -> AnyView
    {
        AnyView(KeyboardNodeView(node: self))
    }
    
    // Internal Funcs
    private func rebuildPorts()
    {
        let portNamesWeNeed = self.keyPresses.compactMap{ self.portNameForKeyPress($0) }
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
                let port = NodePort<Bool>(name: portName, kind: .Outlet)
                
                self.addDynamicPort(port)
                print("add port \(portName) ")
            }
        }
    }
    
    private func portNameForKeyPress(_ keyPress:KeyPress?) -> String?
    {
        guard let keyPress else { return nil }
        
        return keyPress.characters
    }
}
