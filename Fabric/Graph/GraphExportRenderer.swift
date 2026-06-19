//
//  GraphExportRenderer.swift
//  Fabric
//
//  Created by Codex on 4/8/26.
//

import Foundation
import Metal
import Satin
import simd

public enum GraphExportRendererError: Error {
    case alreadyStarted
    case sessionNotStarted
    case commandBufferCreationFailed
    case invalidColorTextureSize(expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case invalidColorTexturePixelFormat(expected: MTLPixelFormat, actual: MTLPixelFormat)
    case invalidDepthTextureSize(expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case invalidDepthTexturePixelFormat(expected: MTLPixelFormat, actual: MTLPixelFormat)
    case commandBufferFailed(Error?)
}

public final class GraphExportRenderer {
    public let graph: Graph
    public let context: Context
    public let size: (width: Int, height: Int)
    public let colorPixelFormat: MTLPixelFormat
    public let depthPixelFormat: MTLPixelFormat
    public let clearColor: simd_float4

    private let graphRenderer: GraphRenderer
    private let renderPassDescriptor = MTLRenderPassDescriptor()

    private var started = false
    private var frameNumber = 0
    private var lastRenderedTime: TimeInterval?

    public init(
        graph: Graph,
        context: Context,
        size: (width: Int, height: Int),
        colorPixelFormat: MTLPixelFormat? = nil,
        depthPixelFormat: MTLPixelFormat? = nil,
        clearColor: simd_float4 = .zero
    ) {
        self.graph = graph
        self.context = context
        self.size = size
        self.colorPixelFormat = colorPixelFormat ?? context.colorPixelFormat
        self.depthPixelFormat = depthPixelFormat ?? context.depthPixelFormat
        self.clearColor = clearColor
        self.graphRenderer = GraphRenderer(context: context)

        self.renderPassDescriptor.colorAttachments[0].loadAction = .clear
        self.renderPassDescriptor.colorAttachments[0].storeAction = .store
        self.renderPassDescriptor.colorAttachments[0].clearColor = .init(clearColor)
        self.renderPassDescriptor.depthAttachment.loadAction = .clear
        self.renderPassDescriptor.depthAttachment.storeAction = .store
        self.renderPassDescriptor.depthAttachment.clearDepth = 1.0
    }

    public func start() {
        guard !self.started else { return }

        self.graphRenderer.resize(
            size: (width: Float(self.size.width), height: Float(self.size.height)),
            scaleFactor: 1.0
        )

        let executionContext = self.makeExecutionContext(
            time: 0,
            deltaTime: 0,
            frameNumber: 0
        )

        self.graphRenderer.enableExecution(graph: self.graph, executionContext: executionContext)
        self.graphRenderer.startExecution(graph: self.graph, executionContext: executionContext)

        self.frameNumber = 0
        self.lastRenderedTime = nil
        self.started = true
    }

    public func renderFrame(
        into colorTexture: MTLTexture,
        depthTexture: MTLTexture? = nil,
        time: TimeInterval
    ) throws {
        guard self.started else {
            throw GraphExportRendererError.sessionNotStarted
        }

        try self.validateColorTexture(colorTexture)
        try self.validateDepthTexture(depthTexture)

        let deltaTime: TimeInterval
        if let lastRenderedTime = self.lastRenderedTime {
            deltaTime = time - lastRenderedTime
        } else {
            deltaTime = 0
        }

        let executionContext = self.makeExecutionContext(
            time: time,
            deltaTime: deltaTime,
            frameNumber: self.frameNumber
        )

        self.renderPassDescriptor.colorAttachments[0].texture = colorTexture
        self.renderPassDescriptor.depthAttachment.texture = depthTexture
        self.renderPassDescriptor.renderTargetWidth = self.size.width
        self.renderPassDescriptor.renderTargetHeight = self.size.height

        guard let commandBuffer = self.graphRenderer.commandQueue.makeCommandBuffer() else {
            throw GraphExportRendererError.commandBufferCreationFailed
        }

        self.graphRenderer.executeAndDraw(
            graph: self.graph,
            executionContext: executionContext,
            renderPassDescriptor: self.renderPassDescriptor,
            commandBuffer: commandBuffer
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.status == .error {
            throw GraphExportRendererError.commandBufferFailed(commandBuffer.error)
        }

        self.lastRenderedTime = time
        self.frameNumber += 1
    }

    public func renderSingleFrame(
        into colorTexture: MTLTexture,
        depthTexture: MTLTexture? = nil,
        time: TimeInterval
    ) throws {
        self.start()
        defer { self.finish() }
        try self.renderFrame(into: colorTexture, depthTexture: depthTexture, time: time)
    }

    public func finish() {
        guard self.started else { return }

        let time = self.lastRenderedTime ?? 0
        let executionContext = self.makeExecutionContext(
            time: time,
            deltaTime: 0,
            frameNumber: self.frameNumber
        )

        self.graphRenderer.disableExecution(graph: self.graph, executionContext: executionContext)
        self.graphRenderer.stopExecution(graph: self.graph, executionContext: executionContext)
        self.graphRenderer.teardown(graph: self.graph)

        self.renderPassDescriptor.colorAttachments[0].texture = nil
        self.renderPassDescriptor.depthAttachment.texture = nil
        self.renderPassDescriptor.renderTargetWidth = 0
        self.renderPassDescriptor.renderTargetHeight = 0

        self.frameNumber = 0
        self.lastRenderedTime = nil
        self.started = false
    }

    private func makeExecutionContext(
        time: TimeInterval,
        deltaTime: TimeInterval,
        frameNumber: Int
    ) -> GraphExecutionContext {
        GraphExecutionContext(
            graphRenderer: self.graphRenderer,
            timing: GraphExecutionTiming(
                time: time,
                deltaTime: deltaTime,
                displayTime: time,
                systemTime: time,
                frameNumber: frameNumber
            ),
            iterationInfo: nil,
            eventInfo: nil
        )
    }

    private func validateColorTexture(_ texture: MTLTexture) throws {
        guard texture.width == self.size.width, texture.height == self.size.height else {
            throw GraphExportRendererError.invalidColorTextureSize(
                expectedWidth: self.size.width,
                expectedHeight: self.size.height,
                actualWidth: texture.width,
                actualHeight: texture.height
            )
        }

        guard texture.pixelFormat == self.colorPixelFormat else {
            throw GraphExportRendererError.invalidColorTexturePixelFormat(
                expected: self.colorPixelFormat,
                actual: texture.pixelFormat
            )
        }
    }

    private func validateDepthTexture(_ texture: MTLTexture?) throws {
        guard let texture else { return }

        guard texture.width == self.size.width, texture.height == self.size.height else {
            throw GraphExportRendererError.invalidDepthTextureSize(
                expectedWidth: self.size.width,
                expectedHeight: self.size.height,
                actualWidth: texture.width,
                actualHeight: texture.height
            )
        }

        guard texture.pixelFormat == self.depthPixelFormat else {
            throw GraphExportRendererError.invalidDepthTexturePixelFormat(
                expected: self.depthPixelFormat,
                actual: texture.pixelFormat
            )
        }
    }
}
