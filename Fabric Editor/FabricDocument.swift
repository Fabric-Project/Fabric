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
                           stencilPixelFormat: .stencil8)

    //    let graph:Graph
    var graphName:String = "Untitled"
    let editingContext: GraphCanvasContext

    @ObservationIgnored var outputWindowManager:DocumentOutputWindowManager? = nil
    @MainActor lazy var movieExportCoordinator = MovieExportCoordinator()
    
    init()
    {
        let graph = Graph(context: self.context)
        self.editingContext = GraphCanvasContext(rootGraph: graph)
    }
    
    init(withTemplate: Bool)
    {
        print("Basic Document Init")
        let graph = Graph(context: self.context)

        // Time source
        let currentTimeNode = CurrentTimeNode(context: self.context)

        // Math expression: secs * speed
        let mathNode = MathExpressionNode(context: self.context, expression: "secs * speed")

        // Publish the 'speed' port with a default of 10
        let speedPort = mathNode.findPort(named: "speed", as: ParameterPort<Float>.self)!
        speedPort.published = true
        speedPort.value = 10

        // Euler orientation (drives mesh rotation on X and Y)
        let eulerNode = EulerOrientationNode(context: self.context)

        // Geometry, material, mesh
        let boxNode = BoxGeometryNode(context: self.context)
        let materialNode = StandardMaterialNode(context: self.context)
        let meshNode = MeshNode(context: self.context)

        // Camera and light
        let cameraNode = PerspectiveCameraNode(context: self.context)
        cameraNode.inputPosition.value = simd_float3(0, 0, 3)

        let directionalLightNode = DirectionalLightNode(context: self.context)
        directionalLightNode.inputPosition.value = SIMD3<Float>(1, 2, 5)

        // Connections — animation chain
        currentTimeNode.outputNumber.connect(to: mathNode.findPort(named: "secs", as: ParameterPort<Float>.self)!)
        mathNode.outputNumber.connect(to: eulerNode.inputX)
        mathNode.outputNumber.connect(to: eulerNode.inputY)
        eulerNode.outputOrientation.connect(to: meshNode.inputOrientation)

        // Connections — geometry
        boxNode.outputGeometry.connect(to: meshNode.inputGeometry)
        materialNode.outputMaterial.connect(to: meshNode.inputMaterial)

        self.editingContext = GraphCanvasContext(rootGraph: graph)

        // Add all nodes to graph
        self.editingContext.currentGraph.addNode(currentTimeNode)
        self.editingContext.currentGraph.addNode(mathNode)
        self.editingContext.currentGraph.addNode(eulerNode)
        self.editingContext.currentGraph.addNode(boxNode)
        self.editingContext.currentGraph.addNode(materialNode)
        self.editingContext.currentGraph.addNode(meshNode)
        self.editingContext.currentGraph.addNode(directionalLightNode)
        self.editingContext.currentGraph.addNode(cameraNode)

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
    func setupOutputWindow()
    {
        self.outputWindowManager = DocumentOutputWindowManager()
        self.outputWindowManager?.ownerDocument = self
        self.outputWindowManager?.setGraph(graph: self.editingContext.rootGraph)
        self.outputWindowManager?.setWindowName(self.graphName)
        ActiveFabricDocumentStore.shared.activeDocument = self
    }
    
    var isOutputPaused: Bool {
        self.outputWindowManager?.isPaused ?? true
    }

    @MainActor
    func toggleOutputPlayback() {
        self.outputWindowManager?.togglePlayback()
    }

    @MainActor
    func closeOutputWindow()
    {
        self.outputWindowManager?.closeOutputWindow()
        if ActiveFabricDocumentStore.shared.activeDocument === self {
            ActiveFabricDocumentStore.shared.activeDocument = nil
        }
    }

    @MainActor
    func exportSnapshotImage()
    {
        let snapshotExportTime = self.outputWindowManager?.snapshotExportTime() ?? 0
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
