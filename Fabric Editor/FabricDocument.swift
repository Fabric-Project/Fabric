//
//  FabricDocument.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import Metal
import Fabric
import Satin

extension UTType {
    static var fabricDocument: UTType {
        UTType(importedAs: "info.HiRez.fabric")
    }
}

class FabricDocument: FileDocument
{
    static var readableContentTypes: [UTType] { [.fabricDocument] }

    @ObservationIgnored let context = Context(device: MTLCreateSystemDefaultDevice()!,
                           sampleCount: 1,
                           colorPixelFormat: .rgba16Float,
                           depthPixelFormat: .depth32Float,
                           stencilPixelFormat: .stencil8)

    //    let graph:Graph
    var graphName:String = "Untitled"
    let editingContext: GraphCanvasContext

    @ObservationIgnored var outputWindowManager:DocumentOutputWindowManager? = nil
    
    init()
    {
        let graph = Graph(context: self.context)
        self.editingContext = GraphCanvasContext(rootGraph: graph)
    }
    
    init(withTemplate: Bool)
    {
        print("Basic Document Init")
        let graph = Graph(context: self.context)

        let boxNode = BoxGeometryNode(context: self.context)
        boxNode.offset = CGSize(width: -400, height:0)

        let materialNode = StandardMaterialNode(context: self.context)
        materialNode.offset = CGSize(width: -400, height: 200)

        let meshNode = MeshNode(context: self.context)
        meshNode.offset = CGSize(width: -200, height: 100)

        let cameraNode = PerspectiveCameraNode(context: self.context)
        cameraNode.offset = CGSize(width: 200 , height: 50)
        cameraNode.inputPosition.value = simd_float3(0, 0, 3)
        
        let directionalLightNode = DirectionalLightNode(context: self.context)
        directionalLightNode.inputPosition.value = SIMD3<Float>(1, 2, 5)
        directionalLightNode.offset = CGSize(width: 0, height: -200)

        boxNode.outputGeometry.connect(to: meshNode.inputGeometry)
        materialNode.outputMaterial.connect(to: meshNode.inputMaterial)

        self.editingContext = GraphCanvasContext(rootGraph: graph)

        self.editingContext.currentGraph.addNode(boxNode)
        self.editingContext.currentGraph.addNode(materialNode)
        self.editingContext.currentGraph.addNode(meshNode)
        self.editingContext.currentGraph.addNode(directionalLightNode)
        self.editingContext.currentGraph.addNode(cameraNode)
    }
    
    required init(configuration: ReadConfiguration) throws
    {
        print("Read Configuration Document Init")

        guard let data = configuration.file.regularFileContents,
              let name = configuration.file.filename
        else
        {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let decoder = JSONDecoder()

        let decodeContext = DecoderContext(documentContext: self.context)
        decoder.context = decodeContext
        
        let graph = try decoder.decode(Graph.self, from: data)

        self.editingContext = GraphCanvasContext(rootGraph: graph)

        self.graphName = name
    }

    deinit
    {
        print("Deinit Closing window for graph: \(self.editingContext.rootGraph.id)")
      
    }

    func setupOutputWindow()
    {
        self.outputWindowManager = DocumentOutputWindowManager()
        self.outputWindowManager?.setGraph(graph: self.editingContext.rootGraph)
        self.outputWindowManager?.setWindowName(self.graphName)
    }
    
    func closeOutputWindow()
    {
        self.outputWindowManager?.closeOutputWindow()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        
        let data = try encoder.encode(self.editingContext.rootGraph)
        
        return .init(regularFileWithContents: data)
    }
}
