//
//  FabricDocument.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Satin
import Metal

extension UTType {
    static var exampleText: UTType {
        UTType(importedAs: "com.example.plain-text")
    }
}

struct FabricDocument: FileDocument {

    @ObservationIgnored let context = Context(device: MTLCreateSystemDefaultDevice()!, sampleCount: 1, colorPixelFormat: MTLPixelFormat.bgra8Unorm, depthPixelFormat: .depth32Float)
    
    let graph:Graph
    @ObservationIgnored let graphRenderer:GraphExecutionEngine
    
    init()
    {
        self.graph = Graph(context: self.context)
        self.graphRenderer = GraphExecutionEngine(context: self.context, graph: self.graph)

        let boxNode = BoxGeometryNode(context: self.context)
//        let materialNode = BasicColorMaterialNode(context: self.context)
        let materialNode = StandardMaterialNode(context: self.context)

        let meshNode = MeshNode(context: self.context)
        let cameraNode = PerspectiveCameraNode(context: self.context)

        let renderNode = RenderNode(context: self.context)
        
        materialNode.outputMaterial.connect(to: meshNode.inputMaterial)
        boxNode.outputGeometry.connect(to: meshNode.inputGeometry)

        meshNode.outputMesh.connect(to: renderNode.inputScene)
        cameraNode.outputCamera.connect(to: renderNode.inputCamera)

        self.graph.addNode(boxNode)
        self.graph.addNode(materialNode)
        self.graph.addNode(meshNode)
        self.graph.addNode(cameraNode)
        self.graph.addNode(renderNode)
    }

    static var readableContentTypes: [UTType] { [.exampleText] }

    init(configuration: ReadConfiguration) throws
    {

        guard let data = configuration.file.regularFileContents
        else
        {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let decoder = JSONDecoder()

        let decodeContext = DecoderContext(documentContext: self.context)
        decoder.context = decodeContext
        
        self.graph =  try decoder.decode(Graph.self, from: data)

        self.graphRenderer = GraphExecutionEngine(context: self.context, graph: self.graph)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        
        let data = try encoder.encode(self.graph)
        
        return .init(regularFileWithContents: data)
    }
}
