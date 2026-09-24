import Foundation
import Satin
import Testing
@testable import Fabric

@Suite("Document File References")
struct DocumentFileReferenceTests
{
    @Test("Absolute file URLs and filesystem paths resolve without a document")
    func absoluteReferencesResolveWithoutDocument()
    {
        let expectedURL = URL(filePath: "/tmp/Fabric Asset.mov").standardizedFileURL

        #expect(DocumentFileReference.resolve(expectedURL.absoluteString, relativeTo: nil) == expectedURL)
        #expect(DocumentFileReference.resolve(expectedURL.path, relativeTo: nil) == expectedURL)
    }

    @Test("Local paths resolve relative to the saved document directory")
    func relativeReferencesUseDocumentDirectory()
    {
        let documentDirectoryURL = URL(filePath: "/tmp/Fabric Project", directoryHint: .isDirectory)
        let expectedURL = documentDirectoryURL
            .appending(path: "Assets/My Image.png")
            .standardizedFileURL

        #expect(DocumentFileReference.resolve("Assets/My Image.png",
                                              relativeTo: documentDirectoryURL) == expectedURL)
        #expect(DocumentFileReference.resolve("Assets/My Image.png", relativeTo: nil) == nil)
    }

    @Test("Bundle export copies assets and rewrites only the exported graph")
    func bundleExportCopiesAndRewrites() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "FabricDocumentBundleTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "source.txt")
        try Data("bundle asset".utf8).write(to: sourceURL)

        let graph = Graph(context: harness.context, fileReferenceBaseURL: rootURL)
        let node = TextFileLoaderNode(context: harness.context)
        node.setFileURL(sourceURL)
        graph.addNode(node)

        let originalReference = try #require(node.inputFilePathParam.value)
        let bundleURL = rootURL.appending(path: "Export.fabricbundle", directoryHint: .isDirectory)
        try DocumentBundleExporter.export(graph: graph, to: bundleURL)

        #expect(node.inputFilePathParam.value == originalReference)
        #expect(FileManager.default.fileExists(
            atPath: bundleURL.appending(path: "Assets/source.txt").path
        ))

        let exportedData = try Data(contentsOf: bundleURL.appending(path: "Graph.fabric"))
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context,
                                         fileReferenceBaseURL: bundleURL)
        let exportedGraph = try decoder.decode(Graph.self, from: exportedData)
        let exportedNode = try #require(exportedGraph.nodes.compactMap { $0 as? TextFileLoaderNode }.first)

        #expect(exportedNode.inputFilePathParam.value == "Assets/source.txt")
        #expect(exportedGraph.resolveFileReference("Assets/source.txt")
            == bundleURL.appending(path: "Assets/source.txt").standardizedFileURL)
    }

    @Test("Bundle export rejects different assets with the same basename")
    func bundleExportRejectsBasenameCollisions() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "FabricDocumentBundleCollisionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let firstDirectoryURL = rootURL.appending(path: "First", directoryHint: .isDirectory)
        let secondDirectoryURL = rootURL.appending(path: "Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstURL = firstDirectoryURL.appending(path: "shared.txt")
        let secondURL = secondDirectoryURL.appending(path: "shared.txt")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)

        let graph = Graph(context: harness.context, fileReferenceBaseURL: rootURL)
        let firstNode = TextFileLoaderNode(context: harness.context)
        firstNode.setFileURL(firstURL)
        graph.addNode(firstNode)
        let secondNode = TextFileLoaderNode(context: harness.context)
        secondNode.setFileURL(secondURL)
        graph.addNode(secondNode)

        let destinationURL = rootURL.appending(path: "Collision.fabricbundle", directoryHint: .isDirectory)

        do
        {
            try DocumentBundleExporter.export(graph: graph, to: destinationURL)
            Issue.record("Expected basename collision to fail export")
        }
        catch let error as DocumentBundleExportError
        {
            guard case .basenameCollision(let name, _, _) = error else
            {
                Issue.record("Unexpected bundle export error: \(error)")
                return
            }

            #expect(name == "shared.txt")
        }
    }

    @Test("Bundle export leaves connected file references dynamic")
    func bundleExportSkipsDynamicReferences() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "FabricDocumentBundleDynamicTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "dynamic.txt")
        try Data("dynamic asset".utf8).write(to: sourceURL)

        let graph = Graph(context: harness.context, fileReferenceBaseURL: rootURL)
        let sourceNode = PassThroughNode<String>(context: harness.context)
        let loaderNode = TextFileLoaderNode(context: harness.context)
        loaderNode.setFileURL(sourceURL)
        graph.addNode(sourceNode)
        graph.addNode(loaderNode)
        graph.connect(sourceNode.output, to: loaderNode.inputFilePathParam)

        let destinationURL = rootURL.appending(path: "Dynamic.fabricbundle", directoryHint: .isDirectory)
        try DocumentBundleExporter.export(graph: graph, to: destinationURL)

        #expect(FileManager.default.fileExists(
            atPath: destinationURL.appending(path: "Assets/dynamic.txt").path
        ) == false)

        let exportedData = try Data(contentsOf: destinationURL.appending(path: "Graph.fabric"))
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context,
                                         fileReferenceBaseURL: destinationURL)
        let exportedGraph = try decoder.decode(Graph.self, from: exportedData)
        let exportedNode = try #require(
            exportedGraph.nodes.compactMap { $0 as? TextFileLoaderNode }.first
        )

        #expect(exportedNode.inputFilePathParam.value == sourceURL.standardizedFileURL.absoluteString)
        #expect(exportedNode.inputFilePathParam.connectedOutlets.isEmpty == false)
        #expect(exportedGraph.connections.count == 1)
    }

    @Test("Bundle document writes preserve existing assets and gather new static references")
    func bundleDocumentWritePreservesAndGathersAssets() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "FabricDocumentBundleWriteTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let newAssetURL = rootURL.appending(path: "new.txt")
        try Data("new asset".utf8).write(to: newAssetURL)

        let graph = Graph(context: harness.context, fileReferenceBaseURL: rootURL)
        let node = TextFileLoaderNode(context: harness.context)
        node.setFileURL(newAssetURL)
        graph.addNode(node)

        let retainedAsset = FileWrapper(regularFileWithContents: Data("retained asset".utf8))
        retainedAsset.preferredFilename = "retained.txt"
        let existingAssets = FileWrapper(directoryWithFileWrappers: [
            "retained.txt": retainedAsset,
        ])
        existingAssets.preferredFilename = DocumentBundleExporter.assetsDirectoryName
        let existingBundle = FileWrapper(directoryWithFileWrappers: [
            DocumentBundleExporter.assetsDirectoryName: existingAssets,
        ])

        let bundleWrapper = try DocumentBundleExporter.fileWrapper(
            graph: graph,
            preserving: existingBundle
        )
        #expect(node.inputFilePathParam.value == "Assets/new.txt")
        #expect((node.inputFilePathParam.parameter as? GenericParameter<String>)?.value == "Assets/new.txt")
        let children = try #require(bundleWrapper.fileWrappers)
        let graphWrapper = try #require(children[DocumentBundleExporter.graphFilename])
        let graphData = try #require(graphWrapper.regularFileContents)
        let assets = try #require(
            children[DocumentBundleExporter.assetsDirectoryName]?.fileWrappers
        )

        #expect(assets["retained.txt"]?.regularFileContents == Data("retained asset".utf8))
        #expect(assets["new.txt"]?.regularFileContents == Data("new asset".utf8))

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context,
                                         fileReferenceBaseURL: rootURL)
        let savedGraph = try decoder.decode(Graph.self, from: graphData)
        let savedNode = try #require(
            savedGraph.nodes.compactMap { $0 as? TextFileLoaderNode }.first
        )
        #expect(savedNode.inputFilePathParam.value == "Assets/new.txt")
    }

    @Test("Save As converts an existing standalone file wrapper into a bundle")
    func standaloneFileWrapperConvertsToBundle() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "FabricStandaloneToBundleTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let assetURL = rootURL.appending(path: "asset.txt")
        try Data("asset".utf8).write(to: assetURL)

        let graph = Graph(context: harness.context, fileReferenceBaseURL: rootURL)
        let node = TextFileLoaderNode(context: harness.context)
        node.setFileURL(assetURL)
        graph.addNode(node)

        let existingStandaloneFile = FileWrapper(
            regularFileWithContents: try JSONEncoder().encode(graph)
        )
        let bundleWrapper = try DocumentBundleExporter.fileWrapper(
            graph: graph,
            preserving: existingStandaloneFile
        )

        #expect(bundleWrapper.isDirectory)
        #expect(bundleWrapper.fileWrappers?[DocumentBundleExporter.graphFilename]?.isRegularFile == true)
        #expect(
            bundleWrapper.fileWrappers?[DocumentBundleExporter.assetsDirectoryName]?
                .fileWrappers?["asset.txt"]?.regularFileContents == Data("asset".utf8)
        )
    }

    @Test("Bundle graphs defer relative LUT loading until their location is known")
    func bundleDecodeDefersRelativeLUTLoading() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "FabricDocumentBundleDeferredLoadTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let movieURL = rootURL.appending(path: "movie.mov")
        try Data().write(to: movieURL)

        let lutURL = rootURL.appending(path: "look.cube")
        let lutContents = """
        LUT_3D_SIZE 2
        0 0 0
        0 0 1
        0 1 0
        0 1 1
        1 0 0
        1 0 1
        1 1 0
        1 1 1
        """
        try lutContents.write(to: lutURL, atomically: true, encoding: .utf8)

        let graph = Graph(context: harness.context, fileReferenceBaseURL: rootURL)
        let movieNode = try MovieProviderNode(context: harness.context, fileURL: movieURL)
        let lutNode = try LUTProcessorNode(context: harness.context, fileURL: lutURL)
        graph.addNode(movieNode)
        graph.addNode(lutNode)
        graph.connect(movieNode.outputTexturePort, to: try #require(lutNode.imageInputPorts().first))

        let bundleURL = rootURL.appending(path: "Deferred.fabricbundle", directoryHint: .isDirectory)
        try DocumentBundleExporter.export(graph: graph, to: bundleURL)

        let exportedData = try Data(contentsOf: bundleURL.appending(path: "Graph.fabric"))
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let decodedGraph = try decoder.decode(Graph.self, from: exportedData)

        let decodedLUTNode = try #require(
            decodedGraph.nodes.compactMap { $0 as? LUTProcessorNode }.first
        )
        #expect(decodedLUTNode.inputFilePathParam.value == "Assets/look.cube")
        #expect(decodedGraph.connections.count == 1)

        decodedGraph.updateFileReferenceBaseURL(bundleURL)
        #expect(decodedGraph.resolveFileReference("Assets/look.cube")
            == bundleURL.appending(path: "Assets/look.cube").standardizedFileURL)
    }

    @Test("Missing runtime files do not prevent user-editable file-reference nodes from deserializing")
    func missingRuntimeFilesDoNotPreventNodeDeserialization() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let missingReference = "Assets/Does Not Exist.asset"
        let graph = Graph(context: harness.context)

        let imageNode = ImageProviderNode(context: harness.context)
        imageNode.inputFilePathParam.value = missingReference
        graph.addNode(imageNode)

        let movieNode = MovieProviderNode(context: harness.context)
        movieNode.inputFilePathParam.value = missingReference
        graph.addNode(movieNode)

        let lutNode = LUTProcessorNode(context: harness.context)
        lutNode.inputFilePathParam.value = missingReference
        graph.addNode(lutNode)

        let modelNode = ModelMeshNode(context: harness.context)
        modelNode.inputFilePathParam.value = missingReference
        graph.addNode(modelNode)

        let instancedModelNode = InstancedModelMeshNode(context: harness.context)
        instancedModelNode.inputFilePathParam.value = missingReference
        graph.addNode(instancedModelNode)

        let textNode = TextFileLoaderNode(context: harness.context)
        textNode.inputFilePathParam.value = missingReference
        graph.addNode(textNode)

        let directoryNode = DirectoryScannerNode(context: harness.context)
        directoryNode.inputPath.value = missingReference
        graph.addNode(directoryNode)

        let data = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let decodedGraph = try decoder.decode(Graph.self, from: data)

        #expect(decodedGraph.missingNodeDiagnostics.isEmpty)
        #expect(decodedGraph.nodes.count == graph.nodes.count)

        let decodedImageNode = try #require(decodedGraph.nodes.compactMap { $0 as? ImageProviderNode }.first)
        let decodedMovieNode = try #require(decodedGraph.nodes.compactMap { $0 as? MovieProviderNode }.first)
        let decodedLUTNode = try #require(decodedGraph.nodes.compactMap { $0 as? LUTProcessorNode }.first)
        let decodedModelNode = try #require(decodedGraph.nodes.compactMap { $0 as? ModelMeshNode }.first)
        let decodedInstancedModelNode = try #require(decodedGraph.nodes.compactMap { $0 as? InstancedModelMeshNode }.first)
        let decodedTextNode = try #require(decodedGraph.nodes.compactMap { $0 as? TextFileLoaderNode }.first)
        let decodedDirectoryNode = try #require(decodedGraph.nodes.compactMap { $0 as? DirectoryScannerNode }.first)

        #expect(decodedImageNode.inputFilePathParam.value == missingReference)
        #expect(decodedImageNode.inputFilePathParam.valueDidChange)
        #expect(decodedMovieNode.inputFilePathParam.value == missingReference)
        #expect(decodedMovieNode.inputFilePathParam.valueDidChange)
        #expect(decodedLUTNode.inputFilePathParam.value == missingReference)
        #expect(decodedLUTNode.inputFilePathParam.valueDidChange)
        #expect(decodedModelNode.inputFilePathParam.value == missingReference)
        #expect(decodedModelNode.inputFilePathParam.valueDidChange)
        #expect(decodedInstancedModelNode.inputFilePathParam.value == missingReference)
        #expect(decodedInstancedModelNode.inputFilePathParam.valueDidChange)
        #expect(decodedTextNode.inputFilePathParam.value == missingReference)
        #expect(decodedTextNode.inputFilePathParam.valueDidChange)
        #expect(decodedDirectoryNode.inputPath.value == missingReference)
        #expect(decodedDirectoryNode.inputPath.valueDidChange)
    }
}
