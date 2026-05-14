//
//  WindowOutputRenderer.swift
//  v
//
//  Created by Anton Marini on 4/29/24.
//

import SwiftUI
import MetalKit
import Fabric
import simd
import AVFoundation

class CAMetalDisplayLinkRenderer: GameView
{
    let graphRenderer:GraphRenderer
    let graph:Graph
    private(set) var lastRenderedGraphTime: TimeInterval?

//    private let commandQueue: (any MTLCommandQueue)
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    

    init(graph:Graph, graphRenderer:GraphRenderer)
    {
        self.graph = graph
        self.graphRenderer = graphRenderer

//        self.commandQueue = self.graph.context.device.makeCommandQueue()!

        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 640, height: 480)))
        
        self.metalLayer.device = self.graph.context.device
        self.metalLayer.framebufferOnly = true
        self.metalLayer.colorspace = nil
        self.metalLayer.pixelFormat = self.graph.context.colorPixelFormat
        self.metalLayer.wantsExtendedDynamicRangeContent = true
        self.metalLayer.displaySyncEnabled = true
        self.metalLayer.maximumDrawableCount = 3
        
        self.renderPassDescriptor.colorAttachments[0].loadAction = .clear;
        self.renderPassDescriptor.colorAttachments[0].storeAction = .store;
        self.renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        
        self.setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit
    {
        print("CAMetalDisplayLinkRenderer Deinit")
    }
    
    func setup()
    {
        self.graphRenderer.enableExecution(graph: graph)
        self.graphRenderer.startExecution(graph: graph)
    }
    
    func teardown()
    {
        print("CAMetalDisplayLinkRenderer Teardown")
                
        self.graphRenderer.disableExecution(graph: self.graph)
        self.graphRenderer.stopExecution(graph: self.graph)
        
        self.graphRenderer.teardown(graph: self.graph)
        
        // 2) Stop/disable the display link (depends on your GameView)
        // If GameView exposes a pause/stop, call it here, e.g.:
        // self.stopDisplayLink()  or  self.isPaused = true
        // (Use whatever your GameView/Forge base provides.)
        
        // 3) Break Metal ties to the layer to avoid callbacks using stale drawables
        self.metalLayer.device = nil
    }
    
    override func renderUpdate(_ update: CAMetalDisplayLink.Update, with deltaTime: CFTimeInterval)
    {
        guard
            let commandBuffer = self.graphRenderer.commandQueue.makeCommandBuffer()//graphRenderer.preDraw()
        else { return }
        
        self.graphRenderer.frameIndex += 1
        
        self.renderPassDescriptor.colorAttachments[0].texture = update.drawable.texture
        self.renderPassDescriptor.renderTargetWidth = update.drawable.texture.width
        self.renderPassDescriptor.renderTargetHeight = update.drawable.texture.height
        
        let timing = GraphExecutionTiming(time: CACurrentMediaTime(),
                                          deltaTime: deltaTime,
                                          displayTime: update.targetPresentationTimestamp,
                                          systemTime: Date.timeIntervalSinceReferenceDate,
                                          frameNumber: self.graphRenderer.frameIndex)
        self.lastRenderedGraphTime = timing.time

        var eventInfo:GraphEventInfo?
        if let event = self.window?.currentEvent
        {
            eventInfo = GraphEventInfo(event:event)
        }
        
        // weird
        let executionInfo = GraphExecutionInfo(timing: timing,
                                               iterationInfo: nil,
                                               eventInfo: eventInfo)
                
        self.graphRenderer.executeAndDraw(graph: graph,
                                     executionInfo: executionInfo,
                                     renderPassDescriptor: self.renderPassDescriptor,
                                     commandBuffer: commandBuffer)
        commandBuffer.present(update.drawable)
        commandBuffer.commit()
    }
        
    override func resizeDrawable(_ scaleFactor: CGFloat)
    {
        super.resizeDrawable(scaleFactor)
        
        self.resize( ( Float(self.frame.size.width * scaleFactor), Float(self.frame.size.height * scaleFactor)) )
    }
    
    // Forge calls resize whenever the view is resized
    func resize(_ size: (width: Float, height: Float))
    {
        self.graphRenderer.resize(size: size, scaleFactor: Float(self.window?.backingScaleFactor ?? 1.0), )
    }
    
    
//#if os(macOS)
//    override func mouseDown(with event: NSEvent) {
//        let pt = normalizePoint(mtkView.convert(event.locationInWindow, from: nil), mtkView.frame.size)
//        intersect(coordinate: pt)
//    }
//    
//    override func mouseDragged(with event: NSEvent) {
//        let pt = normalizePoint(mtkView.convert(event.locationInWindow, from: nil), mtkView.frame.size)
//        intersect(coordinate: pt)
//    }
    
//#elseif os(iOS)
//    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
//        if let first = touches.first {
//            let point = first.location(in: mtkView)
//            let size = mtkView.frame.size
//            let pt = normalizePoint(point, size)
//            intersect(coordinate: pt)
//        }
//    }
//#endif
    
//    func intersect(coordinate: simd_float2) {
//        let results = raycast(camera: camera, coordinate: coordinate, object: scene)
//        if let result = results.first {
//            print(result.object.label)
//            print(result.position)
//            
//            result.object.position = result.position// = simd_float3(x: coordinate.x, y: coordinate.y, z: result.position.z))
//        }
//    }
    
    func normalizePoint(_ point: CGPoint, _ size: CGSize) -> simd_float2 {
#if os(macOS)
        return 2.0 * simd_make_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1.0
#else
        return 2.0 * simd_make_float2(Float(point.x / size.width), 1.0 - Float(point.y / size.height)) - 1.0
#endif
    }
    
    
}
