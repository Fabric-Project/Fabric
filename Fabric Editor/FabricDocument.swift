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

@MainActor
final class ActiveFabricDocumentStore
{
    static let shared = ActiveFabricDocumentStore()

    weak var activeDocument: FabricDocument?

    private init() {}
}

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
                                              stencilPixelFormat: .stencil8,
                                              alphaOitEnabled: true)

    //    let graph:Graph
    var graphName:String = "Untitled"
    let renderer:GraphRenderer
    let editingContext: GraphCanvasContext

    @ObservationIgnored var outputPresenter: OutputPresenter? = nil
    @MainActor lazy var movieExportCoordinator = MovieExportCoordinator()
    
    init()
    {
        let graph = Graph(context: self.context)
        self.editingContext = GraphCanvasContext(rootGraph: graph)
        self.renderer = GraphRenderer(context: self.context, graph: graph)
    }
    
    init(withTemplate: Bool)
    {
        print("Basic Document Init")
        let graph = Graph(context: self.context)

        self.editingContext = GraphCanvasContext(rootGraph: graph)
        self.renderer = GraphRenderer(context: self.context, graph: graph)

        // Spin toggle, published as 'Spin?'
        let spinNode = PassThroughNode<Bool>(context: self.context)
        try? spinNode.enableExecution(renderer: self.renderer)
        try? spinNode.startExecution(renderer: self.renderer)
        spinNode.input.published = true
        spinNode.input.publishedName = "Spin?"
        spinNode.input.value = true

        // Math expression: Amount * Speed, with 'Speed' published
        let mathNode = MathExpressionNode(context: self.context, expression: "Amount * Speed")
        try? mathNode.enableExecution(renderer: self.renderer)
        try? mathNode.startExecution(renderer: self.renderer)

        let speedPort = mathNode.findPort(named: "Speed", as: ParameterPort<Float>.self)!
        speedPort.published = true
        speedPort.value = 10

        // Smooth the stepped speed into a ramp (springy, slightly bouncy)
        let smoothNode = NumberSmoothNode(context: self.context, strategy: SmoothFilterMode.spring)
        try? smoothNode.enableExecution(renderer: self.renderer)
        try? smoothNode.startExecution(renderer: self.renderer)
        smoothNode.findPort(named: "inputDamping", as: ParameterPort<Float>.self)!.value = 0.2

        // Rotation driver: integrates its input every frame
        let integralNode = NumberIntegralNode(context: self.context)
        try? integralNode.enableExecution(renderer: self.renderer)
        try? integralNode.startExecution(renderer: self.renderer)


        // Euler orientation (drives mesh rotation on X and Y). Defaults to
        // the "Euler" strategy, whose inputX/inputY/inputZ/outputOrientation
        // ports are dynamic (added by StrategyNode), hence findPort below
        // instead of typed accessor properties.
        let eulerNode = ComposeOrientationNode(context: self.context)
        try? eulerNode.enableExecution(renderer: self.renderer)
        try? eulerNode.startExecution(renderer: self.renderer)

        // Geometry, material, mesh
        let boxNode = BoxGeometryNode(context: self.context)
        try? boxNode.enableExecution(renderer: self.renderer)
        try? boxNode.startExecution(renderer: self.renderer)

        let materialNode = StandardMaterialNode(context: self.context)
        try? materialNode.enableExecution(renderer: self.renderer)
        try? materialNode.startExecution(renderer: self.renderer)

        let meshNode = MeshNode(context: self.context)
        try? meshNode.enableExecution(renderer: self.renderer)
        try? meshNode.startExecution(renderer: self.renderer)

        // Camera and light
        let cameraNode = PerspectiveCameraNode(context: self.context)
        try? cameraNode.enableExecution(renderer: self.renderer)
        try? cameraNode.startExecution(renderer: self.renderer)
        cameraNode.inputPosition.value = simd_float3(0, 0, 3)

        let directionalLightNode = DirectionalLightNode(context: self.context)
        try? directionalLightNode.enableExecution(renderer: self.renderer)
        try? directionalLightNode.startExecution(renderer: self.renderer)
        directionalLightNode.inputPosition.value = SIMD3<Float>(1, 2, 5)

        // Ports can only register connections after their nodes belong to the graph.
        self.editingContext.currentGraph.addNode(spinNode)
        self.editingContext.currentGraph.addNode(mathNode)
        self.editingContext.currentGraph.addNode(smoothNode)
        self.editingContext.currentGraph.addNode(integralNode)
        self.editingContext.currentGraph.addNode(eulerNode)
        self.editingContext.currentGraph.addNode(boxNode)
        self.editingContext.currentGraph.addNode(materialNode)
        self.editingContext.currentGraph.addNode(meshNode)
        self.editingContext.currentGraph.addNode(directionalLightNode)
        self.editingContext.currentGraph.addNode(cameraNode)

        // Connections — animation chain
        spinNode.output.connect(to: mathNode.findPort(named: "Amount", as: ParameterPort<Float>.self)!)
        mathNode.findPort(named: "result", as: NodePort<Float>.self)!.connect(to: smoothNode.findPort(named: "inputNumber", as: ParameterPort<Float>.self)!)
        smoothNode.findPort(named: "outputNumber", as: NodePort<Float>.self)!.connect(to: integralNode.inputNumber)
        integralNode.outputNumber.connect(to: eulerNode.findPort(named: "inputX", as: ParameterPort<Float>.self)!)
        integralNode.outputNumber.connect(to: eulerNode.findPort(named: "inputY", as: ParameterPort<Float>.self)!)
        eulerNode.findPort(named: "outputOrientation", as: NodePort<simd_float4>.self)!.connect(to: meshNode.inputOrientation)

        // Connections — geometry
        boxNode.outputGeometry.connect(to: meshNode.inputGeometry)
        materialNode.outputMaterial.connect(to: meshNode.inputMaterial)

        // Auto-layout the graph
        self.editingContext.currentGraph.autoLayout()
        
        Task
        {
            await MainActor.run {
                ActiveFabricDocumentStore.shared.activeDocument = self
            }
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
        
        let graph = try decoder.decode(Graph.self, from: data)

        self.editingContext = GraphCanvasContext(rootGraph: graph)
        self.renderer = GraphRenderer(context: self.context, graph: graph)

        self.graphName = name
        
        Task
        {
            await MainActor.run {
                ActiveFabricDocumentStore.shared.activeDocument = self
            }
        }
    }

    deinit
    {
        print("Deinit Closing window for graph: \(self.editingContext.rootGraph.id)")
      
    }

    @MainActor
    func setupOutputPresentation()
    {
        guard self.outputPresenter == nil else { return }

        self.outputPresenter = OutputPresenter(ownerDocument: self, renderer: self.renderer)
        self.outputPresenter?.setWindowTitle(self.graphName)
        ActiveFabricDocumentStore.shared.activeDocument = self
    }

    @MainActor
    func teardownOutputPresentation()
    {
        self.outputPresenter?.teardown()
        self.outputPresenter = nil
        if ActiveFabricDocumentStore.shared.activeDocument === self {
            ActiveFabricDocumentStore.shared.activeDocument = nil
        }
    }

    @MainActor
    func exportSnapshotImage()
    {
        let snapshotExportTime = self.renderer.lastGraphExecutionTime
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = self.defaultImageExportFilename()

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        let configuration = GraphImageExportConfiguration(
            url: url,
            size: (width: 1920, height:1080),
            time: snapshotExportTime,
            format: .png
        )

        let exporter = GraphImageExporter(
            graph: self.editingContext.rootGraph,
            context: self.context,
            configuration: configuration
        )

        do {
            try exporter.export()
        } catch {
            self.presentExportAlert(
                title: "Image Export Failed",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    func exportMovie()
    {
        self.movieExportCoordinator.present(initialSettings: MovieExportSettings(
            startTime: 0,
            duration: 5
        ))
    }

    @MainActor
    func dismissMovieExportSheet()
    {
        self.movieExportCoordinator.dismiss()
    }

    @MainActor
    func continueMovieExport(with exportConfiguration: MovieExportConfiguration)
    {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "mov") ?? .movie]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = self.defaultMovieExportFilename()

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        let configuration = GraphMovieExportConfiguration(
            url: url,
            size: exportConfiguration.size,
            startTime: exportConfiguration.startTime,
            duration: exportConfiguration.duration,
            frameRate: exportConfiguration.frameRate,
            codec: exportConfiguration.codec
        )

        let exporter = GraphMovieExporter(
            graph: self.editingContext.rootGraph,
            context: self.context,
            configuration: configuration
        )

        let totalFrames = configuration.expectedFrameCount ?? 0
        let exportTask = Task {
            do {
                try await exporter.export { completedFrames, totalFrames in
                    self.movieExportCoordinator.updateProgress(
                        completedFrames: completedFrames,
                        totalFrames: totalFrames
                    )
                }

                await MainActor.run {
                    self.movieExportCoordinator.completeExport()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.removeIncompleteMovieExport(at: url)
                    self.movieExportCoordinator.failExport(message: nil)
                }
            } catch {
                await MainActor.run {
                    self.removeIncompleteMovieExport(at: url)
                    self.movieExportCoordinator.failExport(message: error.localizedDescription)
                }
            }
        }

        self.movieExportCoordinator.beginExport(
            destinationURL: url,
            totalFrames: totalFrames,
            task: exportTask
        )
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        
        let data = try encoder.encode(self.editingContext.rootGraph)
        
        return .init(regularFileWithContents: data)
    }

    private func defaultImageExportFilename() -> String
    {
        let sanitizedGraphName = self.graphName.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedGraphName.isEmpty {
            return "Untitled.png"
        }

        return "\(sanitizedGraphName).png"
    }

    private func defaultMovieExportFilename() -> String
    {
        let sanitizedGraphName = self.graphName.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedGraphName.isEmpty {
            return "Untitled.mov"
        }

        return "\(sanitizedGraphName).mov"
    }

    @MainActor
    private func presentExportAlert(title: String, message: String)
    {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @MainActor
    private func removeIncompleteMovieExport(at url: URL)
    {
        if FileManager.default.fileExists(atPath: url.path()) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
