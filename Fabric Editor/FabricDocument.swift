//
//  FabricDocument.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import Satin
import Metal
import Fabric

extension UTType {
    static var fabricDocument: UTType {
        UTType(importedAs: "info.HiRez.fabric")
    }
}

class FabricDocument: FileDocument {

    @ObservationIgnored let context = Context(device: MTLCreateSystemDefaultDevice()!,
                                              sampleCount: 1,
                                              colorPixelFormat: .rgba16Float,
                                              depthPixelFormat: .depth32Float,
                                              stencilPixelFormat: .stencil8)
    
    let graph:Graph
    @ObservationIgnored let graphRenderer:GraphRenderer
    
    var outputwindow:NSWindow? = nil
    var outputRenderer:WindowOutputRenderer2? = nil
    
    init()
    {
        self.graph = Graph(context: self.context)
        self.graphRenderer = GraphRenderer(context: self.context, graph: self.graph)

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

    
    static var readableContentTypes: [UTType] { [.fabricDocument] }

    required init(configuration: ReadConfiguration) throws
    {

        guard let data = configuration.file.regularFileContents,
              let name = configuration.file.preferredFilename
        else
        {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let decoder = JSONDecoder()

        let decodeContext = DecoderContext(documentContext: self.context)
        decoder.context = decodeContext
        
        self.graph =  try decoder.decode(Graph.self, from: data)

        self.graphRenderer = GraphRenderer(context: self.context, graph: self.graph)
        
        self.outputRenderer = WindowOutputRenderer2(context: self.context, graphRenderer: self.graphRenderer)

        Task {
            usleep(1000)
            
            await MainActor.run {
                self.setupWindow(named: name)
            }
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        
        let data = try encoder.encode(self.graph)
        
        return .init(regularFileWithContents: data)
    }
    
    private func setupWindow(named:String)
    {
        self.outputRenderer?.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        
        self.outputwindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600),
                                     styleMask: [.titled, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
                                     backing: .buffered, defer: false)

            
        self.outputwindow!.contentView = self.outputRenderer
        self.outputwindow!.makeKeyAndOrderFront(nil)
        self.outputwindow!.level = .normal // NSWindow.Level(NSWindow.Level.normal.rawValue + 1)
        self.outputwindow!.title = named
    }
}
