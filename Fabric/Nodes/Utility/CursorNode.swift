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
    public let outputCursorPositionInFabricUnits:NodePort<simd_float2>
    public let outputTap:NodePort<Bool>
    public override var ports: [Port] { [self.outputCursorPosition, self.outputCursorPositionInFabricUnits, self.outputTap] + super.ports }
      
    public required init(context: Context)
    {
        self.outputCursorPosition = NodePort<simd_float2>(name: "Position (Pixels)" , kind: .Outlet, description: "Current cursor position in pixels")
        self.outputCursorPositionInFabricUnits = NodePort<simd_float2>(
            name: "Position (Units)",
            kind: .Outlet,
            description: "Current cursor position in Fabric units (-1...1 horizontally, aspect-scaled vertically)"
        )
        self.outputTap = NodePort<Bool>(name: "Tap" , kind: .Outlet, description: "True when mouse button is pressed")
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case outputCursorPositionPort
        case outputCursorPositionInFabricUnitsPort
        case outputTapPort
    }

    override public func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.outputCursorPosition, forKey: .outputCursorPositionPort)
        try container.encode(self.outputCursorPositionInFabricUnits, forKey: .outputCursorPositionInFabricUnitsPort)
        try container.encode(self.outputTap, forKey: .outputTapPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.outputCursorPosition =  try container.decode(NodePort<simd_float2>.self, forKey: .outputCursorPositionPort)
        self.outputCursorPositionInFabricUnits = try container.decodeIfPresent(
            NodePort<simd_float2>.self,
            forKey: .outputCursorPositionInFabricUnitsPort
        ) ?? NodePort<simd_float2>(
            name: "Position (Fabric Units)",
            kind: .Outlet,
            description: "Current cursor position in Fabric units (-1...1 horizontally, aspect-scaled vertically)"
        )
        self.outputTap = try container.decode(NodePort<Bool>.self, forKey: .outputTapPort)

        try super.init(from: decoder)
    }

    static func fabricUnitPosition(
        from pixelPosition: simd_float2,
        renderSize: (width: Float, height: Float)
    ) -> simd_float2
    {
        guard renderSize.width > 0, renderSize.height > 0 else { return .zero }

        let aspect = renderSize.height / renderSize.width
        return simd_float2(
            remap(pixelPosition.x, 0, renderSize.width, -1, 1),
            remap(pixelPosition.y, 0, renderSize.height, -aspect, aspect)
        )
    }

#if os(macOS)
    private func publishCursorPosition(_ point: CGPoint, renderer: GraphRenderer)
    {
        let pixelPosition = simd_float2(
            x: Float(point.x) * renderer.resizeScaleFactor,
            y: Float(point.y) * renderer.resizeScaleFactor
        )
        self.outputCursorPosition.send(pixelPosition)
        self.outputCursorPositionInFabricUnits.send(Self.fabricUnitPosition(
            from: pixelPosition,
            renderSize: renderer.renderEncoder.size
        ))
    }
#endif
    
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
    
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        
#if os(macOS)
        if let event = executionInfo.eventInfo?.event
        {
            if moveEventTypesWeListenFor.contains(event.type)
            {
                self.publishCursorPosition(event.locationInWindow, renderer: renderer)
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
             
                self.publishCursorPosition(event.locationInWindow, renderer: renderer)

            }
        }
      
#endif
        
    }
}
