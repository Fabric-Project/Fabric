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

class FabricDocument: FileDocument
{
    static var readableContentTypes: [UTType] { [.fabricDocument] }

    @ObservationIgnored let context = Context(device: MTLCreateSystemDefaultDevice()!,
                                              sampleCount: 1,
                                              colorPixelFormat: .rgba16Float,
                                              depthPixelFormat: .depth32Float,
                                              stencilPixelFormat: .stencil8)
    
    // TODO - graphRenderer holds a reference to graph
    // We also hold a reference to both - not great
    // graph is @observable so we use in the UI
    // maybe we need to make graphRenderer @observable too?
    let graph:Graph
    @ObservationIgnored let graphRenderer:GraphRenderer
    
    @ObservationIgnored var outputwindow:NSWindow? = nil
    @ObservationIgnored var outputRenderer:WindowOutputRenderer2? = nil
    
    init()
    {
        self.graph = Graph(context: self.context)
        self.graphRenderer = GraphRenderer(context: self.context)
        
        self.graphRenderer.renderer.label = "Document Renderer"
    }
    
    init(withTemplate: Bool)
    {
        print("Basic Document Init")
        self.graph = Graph(context: self.context)
        self.graphRenderer = GraphRenderer(context: self.context)
        self.graphRenderer.renderer.label = "Document Renderer"

        let boxNode = BoxGeometryNode(context: self.context)
        boxNode.offset = CGSize(width: -400, height:0)

        let materialNode = StandardMaterialNode(context: self.context)
        materialNode.offset = CGSize(width: -400, height: 200)

        let meshNode = MeshNode(context: self.context)
        meshNode.offset = CGSize(width: -200, height: 100)

        let cameraNode = PerspectiveCameraNode(context: self.context)
        cameraNode.offset = CGSize(width: 200 , height: 50)

//        let renderNode = RenderNode(context: self.context)
//        renderNode.offset = CGSize(width: 400, height: 0)
//        
//        
//
//        let sceneNode = SceneBuilderNode(context: self.context)
        
        let directionalLightNode = DirectionalLightNode(context: self.context)
        directionalLightNode.inputPosition.value = SIMD3<Float>(1, 2, 5)
        directionalLightNode.offset = CGSize(width: -200, height: -200)

        boxNode.outputGeometry.connect(to: meshNode.inputGeometry)
        materialNode.outputMaterial.connect(to: meshNode.inputMaterial)

//        directionalLightNode.outputLight.connect(to: sceneNode.inputObject1)
//        meshNode.outputMesh.connect(to: sceneNode.inputObject2)
        
//        sceneNode.outputScene.connect(to: renderNode.inputScene)
//        cameraNode.outputCamera.connect(to: renderNode.inputCamera)

        self.graph.addNode(boxNode)
        self.graph.addNode(materialNode)
        self.graph.addNode(meshNode)
//        self.graph.addNode(sceneNode)
        self.graph.addNode(directionalLightNode)
        self.graph.addNode(cameraNode)
//        self.graph.addNode(renderNode)
        
        DispatchQueue.main.async { [weak self] in //asyncAfter(deadline: .now() + 0.1) { [weak self] in
            
            guard let self = self else { return }
            
            print("Init Setting up window for graph: \(self.graph.id)")
            self.setupWindow(named: "Untitled Document")
        }
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
        
        self.graph =  try decoder.decode(Graph.self, from: data)

        self.graphRenderer = GraphRenderer(context: self.context)
        self.graphRenderer.renderer.label = "Document Renderer"

        print("Init config Setting up window for graph: \(self.graph.id)")

        if Thread.isMainThread
        {

            self.setupWindow(named: name)

            print("Init config finished Setting up window for graph: \(self.graph.id)")
        }
        else
        {
            DispatchQueue.main.sync { [weak self] in
                
                guard let self = self else { return }
                
                self.setupWindow(named: name)
                
                print("Init config finished Setting up window for graph: \(self.graph.id)")

            }
        }
    }

    deinit
    {
        print("Deinit Closing window for graph: \(self.graph.id)")
        
        if Thread.isMainThread
        {
            self.outputwindow?.close()
            print("Deinit Finished Closing window for graph: \(self.graph.id)")
        }
        else
        {
            DispatchQueue.main.sync { [weak self] in
                
                guard let self = self else { return }
                
                self.outputwindow?.close()
                
                print("Deinit Finished Closing window for graph: \(self.graph.id)")
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
        
        self.outputwindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600),
                                     styleMask: [.titled, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
                                     backing: .buffered, defer: false)
        self.outputwindow?.isReleasedWhenClosed = true
        
        self.outputRenderer = WindowOutputRenderer2(context: self.context, graph:self.graph, graphRenderer: self.graphRenderer)
        self.outputRenderer?.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
            
        self.outputwindow!.contentView = self.outputRenderer
        self.outputwindow!.makeKeyAndOrderFront(nil)
        self.outputwindow!.level = .normal // NSWindow.Level(NSWindow.Level.normal.rawValue + 1)
        self.outputwindow!.title = named
        self.outputwindow?.isReleasedWhenClosed = false
    }
}
