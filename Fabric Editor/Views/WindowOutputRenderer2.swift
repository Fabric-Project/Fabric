//
//  WindowOutputRenderer.swift
//  v
//
//  Created by Anton Marini on 4/29/24.
//

import SwiftUI
import MetalKit
import Satin
import Fabric
import simd
import AVFoundation

class WindowOutputRenderer2: GameView
{
    let context:Context

    private let commandQueue: (any MTLCommandQueue)
    private let renderPassDescriptor = MTLRenderPassDescriptor()

    weak var graphRenderer:GraphRenderer?

    init(context: Context, graphRenderer:GraphRenderer?)
    {
        self.context = context
        self.graphRenderer = graphRenderer
        self.commandQueue = context.device.makeCommandQueue()!

        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 640, height: 480)))
        
        self.metalLayer.device = context.device
        self.metalLayer.framebufferOnly = true
        self.metalLayer.colorspace = nil
        self.metalLayer.pixelFormat = context.colorPixelFormat
        self.metalLayer.wantsExtendedDynamicRangeContent = true
//        self.metalLayer.displaySyncEnabled = true
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
        print("OutputRenderer Deinit")
    }
    
    func setup()
    {
//
    }
    
    override func renderUpdate(_ update: CAMetalDisplayLink.Update, with deltaTime: CFTimeInterval)
    {
        
        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else { return }
        
        self.renderPassDescriptor.colorAttachments[0].texture = update.drawable.texture
        self.renderPassDescriptor.renderTargetWidth = update.drawable.texture.width
        self.renderPassDescriptor.renderTargetHeight = update.drawable.texture.height

        if let graphRenderer = self.graphRenderer
        {
            graphRenderer.draw(renderPassDescriptor: self.renderPassDescriptor, commandBuffer: commandBuffer)
        }

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
        self.graphRenderer?.resize(size: size, scaleFactor: Float(self.window?.backingScaleFactor ?? 1.0), )
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
