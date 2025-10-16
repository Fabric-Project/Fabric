//
//  RenderInfoNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Satin
import Metal
import simd

#if os(macOS)
import AppKit
#else
import SwiftUI
#endif

public class CursorNode : Node
{
    public override class var name:String { "Cursor" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    
    // Ports
    public let outputCursorPosition:NodePort<simd_float2> = NodePort<simd_float2>(name: "Position" , kind: .Outlet)
    public let outputTap:NodePort<Bool> = NodePort<Bool>(name: "Tap" , kind: .Outlet)
    public override var ports: [AnyPort] { [ self.outputCursorPosition, self.outputTap] + super.ports}
    
    public override var isDirty:Bool { true }
  
#if os(macOS)
    private let moveEventTypesWeListenFor:[NSEvent.EventType] = [
        .mouseMoved
        ]
    
    private let downEventTypesWeListenFor:[NSEvent.EventType] = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,

        ]
    
    private let upEventTypesWeListenFor:[NSEvent.EventType] = [
        .leftMouseUp,
        .rightMouseUp,
        .otherMouseUp,
        ]


    private var eventTypesWeListenFor:[NSEvent.EventType] {
        moveEventTypesWeListenFor + downEventTypesWeListenFor + upEventTypesWeListenFor
    }

#endif
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
#if os(macOS)
        if let event = context.eventInfo?.event
        {
            if moveEventTypesWeListenFor.contains(event.type)
            {
                let point = event.locationInWindow
                self.outputCursorPosition.send( simd_float2(x: Float(point.x), y: Float(point.y)) )
            }
            
            if upEventTypesWeListenFor.contains(event.type)
            {
                self.outputTap.send( false )
            }
            else if downEventTypesWeListenFor.contains(event.type)
            {
                self.outputTap.send( true )
            }
        }
      
#endif
        
    }
}
