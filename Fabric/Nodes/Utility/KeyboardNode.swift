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

extension EventModifiers : @retroactive Sequence
{
    
}

extension EventModifiers
{
    public var description: String
    {
        switch self
        {
        case .capsLock: return "Caps Lock &"
        case .command: return "Command &"
        case .control: return "Control &"
        case .option: return "Option &"
        case .shift: return "Shift &"
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
    @State private var keyPress:KeyPress? = nil

     var body: some View {
         Text("Key Press: \(keyPress?.modifiers.completeDescription ?? "")  \(keyPress?.characters ?? "")")
             .focusable()
             .focused($focused)
             .onKeyPress(phases: .down) { press in
                 keyPress = press
                 return .handled
             }
             .onAppear {
                 focused = true
             }
             .lineLimit(1)
             .font(.system(size: 10))
             .textFieldStyle(RoundedBorderTextFieldStyle())
     }
}

struct KeyboardNodeView : View
{
    @Bindable var node:KeyboardNode
    
    var body: some View
    {
        @Bindable var bindableNode = node

        VStack(alignment: .leading)
        {
            Text("Configure Keyboard Output")
            
            KeyboardKeyConfigView()
            
            Spacer()
            
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
    
    
    // Settings View
    
    override public func providesSettingsView() -> Bool {
        true
    }
    
    override public func settingsView() -> AnyView
    {
        AnyView(KeyboardNodeView(node: self))
    }
}
