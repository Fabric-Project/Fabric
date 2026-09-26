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
        #expect(DocumentFileReference.reference(for: expectedURL, relativeTo: nil) == expectedURL.absoluteString)
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

    @Test("Relative paths include parent directories and preserve literal filename characters")
    func relativePathRoundTrips()
    {
        let directoryURL = URL(filePath: "/tmp/Project/Graphs", directoryHint: .isDirectory)
        for path in ["/tmp/Project/Graphs/Assets/image.png", "/tmp/Project/Shared/My #100% image.png",
                     "/Volumes/Media/movie.mov", "/tmp/Project/Graphs"]
        {
            let sourceURL = URL(filePath: path).standardizedFileURL
            let reference = DocumentFileReference.reference(for: sourceURL, relativeTo: directoryURL)
            #expect(DocumentFileReference.resolve(reference, relativeTo: directoryURL)?.path == sourceURL.path)
        }
        #expect(DocumentFileReference.reference(for: URL(filePath: "/tmp/Project/Shared/image.png"),
                                                   relativeTo: directoryURL) == "../Shared/image.png")
    }

    @Test("First save rewrites live ports and parameters and persists relative references")
    func firstSaveRewritesLiveAndSavedGraph() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let node = TextFileLoaderNode(context: harness.context)
        let directoryURL = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
        let sourceURL = directoryURL.appending(path: "Assets/source.txt")
        node.setFileURL(sourceURL)
        graph.addNode(node)
        node.normalizeFileReference(node.inputFilePathParam)
        #expect(node.inputFilePathParam.value == sourceURL.absoluteString)

        graph.rewriteFileReferences(relativeTo: directoryURL)
        #expect(node.inputFilePathParam.value == "Assets/source.txt")
        #expect((node.inputFilePathParam.parameter as? GenericParameter<String>)?.value == "Assets/source.txt")

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let reopenedGraph = try decoder.decode(Graph.self, from: JSONEncoder().encode(graph))
        reopenedGraph.updateFileReferenceBaseURL(directoryURL)
        let reopenedNode = try #require(reopenedGraph.nodes.first as? TextFileLoaderNode)
        #expect(reopenedNode.inputFilePathParam.value == "Assets/source.txt")
        #expect(reopenedGraph.resolveFileReference(try #require(reopenedNode.inputFilePathParam.value)) == sourceURL)
    }

    @Test("File loaders consume raw picker URLs and graph save handles other paths")
    func fileAssignmentsUseDocumentLocation() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let directoryURL = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
        let graph = Graph(context: harness.context, fileReferenceBaseURL: directoryURL)
        let node = TextFileLoaderNode(context: harness.context)
        node.setFileURL(directoryURL.appending(path: "before-add.txt"))
        graph.addNode(node)
        #expect(node.inputFilePathParam.value == directoryURL.appending(path: "before-add.txt").absoluteString)
        node.normalizeFileReference(node.inputFilePathParam)
        #expect(node.inputFilePathParam.value == "before-add.txt")
        node.setFileURL(directoryURL.appending(path: "after-add.txt"))
        #expect(node.inputFilePathParam.value == "after-add.txt")
        node.inputFilePathParam.value = "/tmp/shared.txt"
        #expect(node.inputFilePathParam.value == "/tmp/shared.txt")
        graph.rewriteFileReferences(relativeTo: directoryURL)
        #expect(node.inputFilePathParam.value == "../shared.txt")
        let parameter = try #require(node.inputFilePathParam.parameter as? GenericParameter<String>)
        let pickedURL = directoryURL.appending(path: "Picked #1.txt")
        parameter.value = pickedURL.absoluteString
        #expect(node.inputFilePathParam.value == pickedURL.absoluteString)
        node.normalizeFileReference(node.inputFilePathParam)
        #expect(node.inputFilePathParam.value == "Picked #1.txt")
        #expect(parameter.value == "Picked #1.txt")
        parameter.value = ""
        #expect(node.inputFilePathParam.value == "")
    }

    @Test("Save As preserves targets throughout nested graphs")
    func saveAsRebasesNestedReferences() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let oldDirectory = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
        let newDirectory = oldDirectory.appending(path: "Versions", directoryHint: .isDirectory)
        let graph = Graph(context: harness.context, fileReferenceBaseURL: oldDirectory)
        let subgraphNode = SubgraphNode(context: harness.context)
        let loader = TextFileLoaderNode(context: harness.context)
        loader.setFileURL(oldDirectory.appending(path: "Assets/source.txt"))
        subgraphNode.subGraph.addNode(loader)
        graph.addNode(subgraphNode)
        graph.rewriteFileReferences(relativeTo: oldDirectory)
        #expect(loader.inputFilePathParam.value == "Assets/source.txt")

        graph.rewriteFileReferences(relativeTo: newDirectory)
        #expect(loader.inputFilePathParam.value == "../Assets/source.txt")
        #expect(subgraphNode.subGraph.fileReferenceBaseURL == newDirectory)
        #expect(subgraphNode.subGraph.resolveFileReference(try #require(loader.inputFilePathParam.value))
            == oldDirectory.appending(path: "Assets/source.txt"))
        graph.rewriteFileReferences(relativeTo: newDirectory)
        #expect(loader.inputFilePathParam.value == "../Assets/source.txt")
    }

    @Test("Reopening a moved project retains its relative references")
    func movedProjectUsesNewLocation() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let graph = Graph(context: harness.context)
        let node = TextFileLoaderNode(context: harness.context)
        graph.addNode(node)
        node.inputFilePathParam.value = "Assets/source.txt"
        let movedDirectory = URL(filePath: "/tmp/Moved Project", directoryHint: .isDirectory)
        graph.updateFileReferenceBaseURL(movedDirectory)
        #expect(node.inputFilePathParam.value == "Assets/source.txt")
        #expect(graph.resolveFileReference(try #require(node.inputFilePathParam.value))
            == movedDirectory.appending(path: "Assets/source.txt"))
    }

    @Test("Connected file paths survive rebasing and decoding unchanged")
    func connectedPathsRemainDynamic() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }
        let directoryURL = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
        let graph = Graph(context: harness.context, fileReferenceBaseURL: directoryURL)
        let source = PassThroughNode<String>(context: harness.context)
        let loader = TextFileLoaderNode(context: harness.context)
        graph.addNode(source)
        graph.addNode(loader)
        graph.connect(source.output, to: loader.inputFilePathParam)
        let reference = "file:///tmp/Project/dynamic.txt"
        source.output.send(reference, force: true)
        loader.normalizeFileReference(loader.inputFilePathParam)
        #expect(loader.inputFilePathParam.value == reference)
        graph.rewriteFileReferences(relativeTo: directoryURL.appending(path: "Versions"))
        #expect(loader.inputFilePathParam.value == reference)

        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context, fileReferenceBaseURL: directoryURL)
        let decodedGraph = try decoder.decode(Graph.self, from: JSONEncoder().encode(graph))
        let decodedLoader = try #require(decodedGraph.nodes.compactMap { $0 as? TextFileLoaderNode }.first)
        #expect(decodedLoader.inputFilePathParam.value == reference)
        #expect(decodedGraph.connections.count == 1)
        #expect(decodedLoader.inputFilePathParam.connectedOutlets.isEmpty == false)
    }

    @Test("Graphs defer relative LUT loading until their location is known")
    func decodeDefersRelativeLUTLoading() throws
    {
        guard let harness = GraphExecutionTestHarness() else { return }

        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "FabricRelativeDeferredLoadTests-\(UUID().uuidString)",
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

        graph.rewriteFileReferences(relativeTo: rootURL)
        let exportedData = try JSONEncoder().encode(graph)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: harness.context)
        let decodedGraph = try decoder.decode(Graph.self, from: exportedData)

        let decodedLUTNode = try #require(
            decodedGraph.nodes.compactMap { $0 as? LUTProcessorNode }.first
        )
        #expect(decodedLUTNode.inputFilePathParam.value == "look.cube")
        #expect(decodedGraph.connections.count == 1)

        decodedGraph.updateFileReferenceBaseURL(rootURL)
        #expect(decodedGraph.resolveFileReference("look.cube")
            == rootURL.appending(path: "look.cube").standardizedFileURL)
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
