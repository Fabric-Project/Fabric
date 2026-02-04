//
//  CursorNode.swift
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
    override public class var name:String { "Cursor" }
    override public class var nodeType:Node.NodeType { Node.NodeType.Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }

    // Execution mode value is used to determine when this node is evaluated
    override public class var nodeTimeMode: Node.TimeMode { .None }

    // User interface description
    override public class var nodeDescription: String { "Provides Cursor (Mouse or Touch) Position and Button / Tap state" }

    // Ports
    public let outputCursorPosition:NodePort<simd_float2>
    public let outputTap:NodePort<Bool>
    public override var ports: [Port] { [ self.outputCursorPosition, self.outputTap] + super.ports}
      
    public required init(context: Context)
    {
        self.outputCursorPosition = NodePort<simd_float2>(name: "Position" , kind: .Outlet, description: "Current cursor position in pixels")
        self.outputTap = NodePort<Bool>(name: "Tap" , kind: .Outlet, description: "True when mouse button is pressed")
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case outputCursorPositionPort
        case outputTapPort
    }

    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputCursorPosition, forKey: .outputCursorPositionPort)
        try container.encode(self.outputTap, forKey: .outputTapPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputCursorPosition =  try container.decode(NodePort<simd_float2>.self, forKey: .outputCursorPositionPort)
        self.outputTap = try container.decode(NodePort<Bool>.self, forKey: .outputTapPort)

        try super.init(from: decoder)
    }
    
#if os(macOS)
    private let moveEventTypesWeListenFor:[NSEvent.EventType] = [
        .mouseMoved
        ]
    
    private let downEventTypesWeListenFor:[NSEvent.EventType] = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged
        
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
    
    
    override public func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        
#if os(macOS)
        if let event = context.eventInfo?.event,
           let graphRenderer = context.graphRenderer
        {
            if moveEventTypesWeListenFor.contains(event.type)
            {
                let point = event.locationInWindow
                self.outputCursorPosition.send( simd_float2(x: Float(point.x) * graphRenderer.resizeScaleFactor, y: Float(point.y) * graphRenderer.resizeScaleFactor) )
            }
            
            if upEventTypesWeListenFor.contains(event.type)
            {
                print("Cursor Up")
                self.outputTap.send( false )
            }
            else if downEventTypesWeListenFor.contains(event.type)
            {
                print("Cursor Down")
                self.outputTap.send( true )
             
                let point = event.locationInWindow
                self.outputCursorPosition.send( simd_float2(x: Float(point.x) * graphRenderer.resizeScaleFactor, y: Float(point.y) * graphRenderer.resizeScaleFactor) )

            }
        }
      
#endif
        
    }
}
