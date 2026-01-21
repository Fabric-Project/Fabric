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
             
             Button("Binding \(self.keypressIndex + 1)") {
                 self.focused = true
             }
             
             Text("Key Press: \(keyPress?.modifiers.completeDescription ?? "")  \(keyPress?.key.description ?? "")")
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

            ForEach( 0 ..< self.node.keyPresses.count, id:\.self ) { keyPressIdx in
                
                KeyboardKeyConfigView(node:node, keypressIndex: keyPressIdx)
            }
            
            Spacer()
            
            HStack
            {
                Button("-") {
                    if self.node.keyPresses.isEmpty { return }
                    
                    self.node.keyPresses.removeLast()
                }
                
                Button("+") {
                    self.node.keyPresses.append(nil)

                }
            }
        }
    }
}


public class KeyboardNode : Node
{
    override public class var name:String { "Keyboard" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Configure and detect keypresses"}

    // Ports
            
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
      
    }
    
     fileprivate var keyPresses:[KeyPress?] = [nil]
    
    // Settings View
    
    override public func providesSettingsView() -> Bool {
        true
    }
    
    override public func settingsView() -> AnyView
    {
        AnyView(KeyboardNodeView(node: self))
    }
}
