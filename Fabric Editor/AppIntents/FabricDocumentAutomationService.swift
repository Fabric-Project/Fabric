//
//  FabricDocumentAutomationService.swift
//  Fabric Editor
//
//  Created by Codex on 4/7/26.
//

import AppIntents
import AppKit
import Fabric
import Foundation
import Metal
import Satin
import simd

enum FabricIntentError: LocalizedError {
    case invalidGraphFile
    case invalidGraphURL(String)
    case unsupportedGraphFile(URL)
    case fileAlreadyExists(URL)
    case graphHasNoFile(String)
    case nodeNotFound(String)
    case portNotFound(String)
    case publishedParameterNotFound(String)
    case notAPublishedParameter(String)
    case unsupportedParameterType(String)
    case invalidValue(String)
    case incompatiblePorts(String)
    case registryNodeNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidGraphFile:
            return "Select a valid Fabric graph file."
        case .invalidGraphURL(let value):
            return "Invalid graph URL: \(value)"
        case .unsupportedGraphFile(let url):
            return "Unsupported graph file: \(url.path)"
        case .fileAlreadyExists(let url):
            return "A graph already exists at \(url.path)"
        case .graphHasNoFile(let name):
            return "\(name) has not been saved to disk yet."
        case .nodeNotFound(let nodeID):
            return "Node not found: \(nodeID)"
        case .portNotFound(let portID):
            return "Port not found: \(portID)"
        case .publishedParameterNotFound(let parameterID):
            return "Published parameter not found: \(parameterID)"
        case .notAPublishedParameter(let portID):
            return "Port is not published: \(portID)"
        case .unsupportedParameterType(let label):
            return "Unsupported parameter type for '\(label)'"
        case .invalidValue(let description):
            return "Invalid value: \(description)"
        case .incompatiblePorts(let description):
            return "Incompatible ports: \(description)"
        case .registryNodeNotFound(let identifier):
            return "Registry node not found: \(identifier)"
        }
    }
}

enum FabricPortKindAppEnum: String, AppEnum {
    case inlet
    case outlet

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Port Kind"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .inlet: "Inlet",
        .outlet: "Outlet",
    ]

    init?(portKind: PortKind) {
        switch portKind {
        case .Inlet:
            self = .inlet
        case .Outlet:
            self = .outlet
        }
    }
}

@MainActor
final class FabricDocumentAutomationService {
    static let shared = FabricDocumentAutomationService()

    struct LoadedGraph {
        let fileURL: URL?
        let graphURL: String
        let graph: Graph
    }

    private let untitledScheme = "fabric-untitled"
    private var untitledGraphs: [String: Graph] = [:]

    private init() {}

    func openGraph(file: IntentFile) throws -> FabricGraphEntity {
        let url = try self.graphURL(from: file)
        NSWorkspace.shared.open(url)
        let loadedGraph = try self.loadGraph(at: url)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: loadedGraph.fileURL)
    }

    func createGraph(useTemplate: Bool) -> FabricGraphEntity {
        let document = useTemplate ? FabricDocument(withTemplate: true) : FabricDocument()
        let graph = document.editingContext.rootGraph
        self.untitledGraphs[graph.id.uuidString] = graph
        return self.makeGraphEntity(graph: graph, fileURL: nil)
    }

    func graphDetails(for graphEntity: FabricGraphEntity) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(for: graphEntity)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: loadedGraph.fileURL)
    }

    func saveGraph(_ graphEntity: FabricGraphEntity) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(for: graphEntity)
        let saveURL = if let fileURL = loadedGraph.fileURL {
            fileURL
        } else {
            try self.defaultUntitledSaveURL()
        }
        try self.saveGraph(loadedGraph.graph, to: saveURL)
        self.untitledGraphs.removeValue(forKey: loadedGraph.graph.id.uuidString)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: saveURL)
    }

    func revealGraphFile(for graphEntity: FabricGraphEntity) throws -> IntentFile {
        guard let url = try self.fileURL(for: graphEntity) else {
            throw FabricIntentError.graphHasNoFile(graphEntity.displayName)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return IntentFile(fileURL: url)
    }

    func listRegistryNodes() -> [FabricRegistryNodeEntity] {
        self.listRegistryNodes(matching: nil)
    }

    func listRegistryNodes(matching searchText: String?) -> [FabricRegistryNodeEntity] {
        let normalizedSearchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NodeRegistry.shared.availableNodes.filter { wrapper in
            if let normalizedSearchText, !normalizedSearchText.isEmpty {
                let haystack = [
                    wrapper.nodeName,
                    String(describing: wrapper.nodeClass),
                    wrapper.nodeType.description,
                    wrapper.nodeDescription,
                ]
                return haystack.contains { $0.localizedStandardContains(normalizedSearchText) }
            }

            return true
        }
        .map { self.makeRegistryNodeEntity(wrapper: $0) }
    }

    func registryNodeDetails(for registryNode: FabricRegistryNodeEntity) throws -> FabricRegistryNodeEntity {
        let wrapper = try self.registryWrapper(for: registryNode)
        return self.makeRegistryNodeEntity(wrapper: wrapper)
    }

    func listNodes(in graphEntity: FabricGraphEntity) throws -> [FabricNodeEntity] {
        let loadedGraph = try self.loadGraph(for: graphEntity)
        return loadedGraph.graph.nodes.map { self.makeNodeEntity(node: $0, graphURL: loadedGraph.graphURL) }
    }

    func findNodes(in graphEntity: FabricGraphEntity, matching searchText: String) throws -> [FabricNodeEntity] {
        let loadedGraph = try self.loadGraph(for: graphEntity)
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return loadedGraph.graph.nodes.compactMap { node in
            guard !normalizedSearchText.isEmpty else {
                return self.makeNodeEntity(node: node, graphURL: loadedGraph.graphURL)
            }

            let haystack = [
                node.name,
                String(describing: type(of: node)),
                node.nodeType.description,
            ]
            let matches = haystack.contains { $0.localizedStandardContains(normalizedSearchText) }
            return matches ? self.makeNodeEntity(node: node, graphURL: loadedGraph.graphURL) : nil
        }
    }

    func nodeDetails(for nodeEntity: FabricNodeEntity) throws -> FabricNodeEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: nodeEntity.graphURL)
        let node = try self.node(withIdentifier: nodeEntity.nodeIdentifier, in: loadedGraph.graph)
        return self.makeNodeEntity(node: node, graphURL: loadedGraph.graphURL)
    }

    func listPorts(for nodeEntity: FabricNodeEntity) throws -> [FabricPortEntity] {
        let loadedGraph = try self.loadGraph(forGraphURL: nodeEntity.graphURL)
        let node = try self.node(withIdentifier: nodeEntity.nodeIdentifier, in: loadedGraph.graph)
        return node.ports.map { self.makePortEntity(port: $0, graphURL: loadedGraph.graphURL) }
    }

    func findPorts(
        for nodeEntity: FabricNodeEntity,
        matching searchText: String,
        kind: FabricPortKindAppEnum?,
        publishedOnly: Bool
    ) throws -> [FabricPortEntity] {
        let loadedGraph = try self.loadGraph(forGraphURL: nodeEntity.graphURL)
        let node = try self.node(withIdentifier: nodeEntity.nodeIdentifier, in: loadedGraph.graph)
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return node.ports.filter { port in
            if publishedOnly, !port.published {
                return false
            }

            if let kind, FabricPortKindAppEnum(portKind: port.kind) != kind {
                return false
            }

            if !normalizedSearchText.isEmpty {
                let haystack = [
                    port.name,
                    port.displayName,
                    port.portType.rawValue,
                ]
                return haystack.contains { $0.localizedStandardContains(normalizedSearchText) }
            }

            return true
        }
        .map { self.makePortEntity(port: $0, graphURL: loadedGraph.graphURL) }
    }

    func listPublishedParameters(in graphEntity: FabricGraphEntity) throws -> [FabricPublishedParameterEntity] {
        let loadedGraph = try self.loadGraph(for: graphEntity)
        return self.publishedParameters(in: loadedGraph.graph, graphURL: loadedGraph.graphURL)
    }

    func findPublishedParameters(in graphEntity: FabricGraphEntity, matching searchText: String) throws -> [FabricPublishedParameterEntity] {
        let loadedGraph = try self.loadGraph(for: graphEntity)
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return self.publishedParameters(in: loadedGraph.graph, graphURL: loadedGraph.graphURL).filter { parameter in
            guard !normalizedSearchText.isEmpty else { return true }
            let haystack = [
                parameter.label,
                parameter.parameterType,
                parameter.controlType,
                parameter.valueSummary,
            ]
            return haystack.contains { $0.localizedStandardContains(normalizedSearchText) }
        }
    }

    func publishedParameterDetails(for parameterEntity: FabricPublishedParameterEntity) throws -> FabricPublishedParameterEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: parameterEntity.graphURL)
        let parameterPort = try self.publishedPort(withIdentifier: parameterEntity.publishedPortIdentifier, in: loadedGraph.graph)
        guard let parameter = parameterPort.parameter else {
            throw FabricIntentError.unsupportedParameterType(parameterEntity.label)
        }
        return self.makePublishedParameterEntity(parameter: parameter, port: parameterPort, graphURL: loadedGraph.graphURL)
    }

    func addNode(
        registryNode: FabricRegistryNodeEntity,
        to graphEntity: FabricGraphEntity,
        x: Double?,
        y: Double?
    ) throws -> FabricNodeEntity {
        let loadedGraph = try self.loadGraph(for: graphEntity)
        let wrapper = try self.registryWrapper(for: registryNode)
        let node = try wrapper.initializeNode(context: loadedGraph.graph.context)

        if let x, let y {
            node.offset = CGSize(width: x, height: y)
        }

        loadedGraph.graph.addNode(node)
        try self.persistGraph(loadedGraph)
        return self.makeNodeEntity(node: node, graphURL: loadedGraph.graphURL)
    }

    func removeNode(_ nodeEntity: FabricNodeEntity) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: nodeEntity.graphURL)
        let node = try self.node(withIdentifier: nodeEntity.nodeIdentifier, in: loadedGraph.graph)
        loadedGraph.graph.delete(node: node)
        try self.persistGraph(loadedGraph)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: loadedGraph.fileURL)
    }

    func connectPorts(from sourcePortEntity: FabricPortEntity, to destinationPortEntity: FabricPortEntity) throws -> FabricGraphEntity {
        guard sourcePortEntity.graphURL == destinationPortEntity.graphURL else {
            throw FabricIntentError.incompatiblePorts("Ports must belong to the same graph")
        }

        let loadedGraph = try self.loadGraph(forGraphURL: sourcePortEntity.graphURL)
        let source = try self.port(withIdentifier: sourcePortEntity.portIdentifier, in: loadedGraph.graph)
        let destination = try self.port(withIdentifier: destinationPortEntity.portIdentifier, in: loadedGraph.graph)

        guard source.kind == .Outlet, destination.kind == .Inlet else {
            throw FabricIntentError.incompatiblePorts("Connect an outlet source to an inlet destination")
        }

        guard source.canConnect(to: destination) else {
            throw FabricIntentError.incompatiblePorts("\(source.displayName) cannot connect to \(destination.displayName)")
        }

        source.connect(to: destination)
        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.persistGraph(loadedGraph)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: loadedGraph.fileURL)
    }

    func disconnectPorts(from sourcePortEntity: FabricPortEntity, to destinationPortEntity: FabricPortEntity?) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: sourcePortEntity.graphURL)
        let source = try self.port(withIdentifier: sourcePortEntity.portIdentifier, in: loadedGraph.graph)

        if let destinationPortEntity {
            let destination = try self.port(withIdentifier: destinationPortEntity.portIdentifier, in: loadedGraph.graph)
            source.disconnect(from: destination)
        } else {
            source.disconnectAll()
        }

        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.persistGraph(loadedGraph)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: loadedGraph.fileURL)
    }

    func publishPort(_ portEntity: FabricPortEntity, label: String?) throws -> FabricPublishedParameterEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: portEntity.graphURL)
        let port = try self.port(withIdentifier: portEntity.portIdentifier, in: loadedGraph.graph)
        port.published = true

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        port.publishedName = trimmedLabel?.isEmpty == false ? trimmedLabel : nil

        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.persistGraph(loadedGraph)

        guard let parameter = port.parameter else {
            throw FabricIntentError.unsupportedParameterType(port.displayName)
        }

        return self.makePublishedParameterEntity(parameter: parameter, port: port, graphURL: loadedGraph.graphURL)
    }

    func unpublishPort(_ portEntity: FabricPortEntity) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: portEntity.graphURL)
        let port = try self.port(withIdentifier: portEntity.portIdentifier, in: loadedGraph.graph)
        port.published = false
        port.publishedName = nil
        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.persistGraph(loadedGraph)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: loadedGraph.fileURL)
    }

    func unpublishParameter(_ parameterEntity: FabricPublishedParameterEntity) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: parameterEntity.graphURL)
        let port = try self.publishedPort(withIdentifier: parameterEntity.publishedPortIdentifier, in: loadedGraph.graph)
        port.published = false
        port.publishedName = nil
        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.persistGraph(loadedGraph)
        return self.makeGraphEntity(graph: loadedGraph.graph, fileURL: loadedGraph.fileURL)
    }

    func setPublishedBoolean(_ parameterEntity: FabricPublishedParameterEntity, value: Bool) throws -> FabricPublishedParameterEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: parameterEntity.graphURL)
        let publishedPort = try self.publishedPort(withIdentifier: parameterEntity.publishedPortIdentifier, in: loadedGraph.graph)
        let parameter = try self.parameter(forPublishedPort: publishedPort, label: parameterEntity.label)
        guard let boolParameter = parameter as? BoolParameter else {
            throw FabricIntentError.unsupportedParameterType(parameterEntity.label)
        }
        boolParameter.value = value
        return try self.persistParameterUpdate(graph: loadedGraph, publishedPort: publishedPort, label: parameterEntity.label)
    }

    func setPublishedNumber(_ parameterEntity: FabricPublishedParameterEntity, value: Double) throws -> FabricPublishedParameterEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: parameterEntity.graphURL)
        let publishedPort = try self.publishedPort(withIdentifier: parameterEntity.publishedPortIdentifier, in: loadedGraph.graph)
        let parameter = try self.parameter(forPublishedPort: publishedPort, label: parameterEntity.label)

        if let floatParameter = parameter as? FloatParameter {
            floatParameter.value = Float(value)
        } else if let doubleParameter = parameter as? DoubleParameter {
            doubleParameter.value = value
        } else {
            throw FabricIntentError.unsupportedParameterType(parameterEntity.label)
        }

        return try self.persistParameterUpdate(graph: loadedGraph, publishedPort: publishedPort, label: parameterEntity.label)
    }

    func setPublishedInteger(_ parameterEntity: FabricPublishedParameterEntity, value: Int) throws -> FabricPublishedParameterEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: parameterEntity.graphURL)
        let publishedPort = try self.publishedPort(withIdentifier: parameterEntity.publishedPortIdentifier, in: loadedGraph.graph)
        let parameter = try self.parameter(forPublishedPort: publishedPort, label: parameterEntity.label)

        if let intParameter = parameter as? IntParameter {
            intParameter.value = value
        } else {
            throw FabricIntentError.unsupportedParameterType(parameterEntity.label)
        }

        return try self.persistParameterUpdate(graph: loadedGraph, publishedPort: publishedPort, label: parameterEntity.label)
    }

    func setPublishedText(_ parameterEntity: FabricPublishedParameterEntity, value: String) throws -> FabricPublishedParameterEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: parameterEntity.graphURL)
        let publishedPort = try self.publishedPort(withIdentifier: parameterEntity.publishedPortIdentifier, in: loadedGraph.graph)
        let parameter = try self.parameter(forPublishedPort: publishedPort, label: parameterEntity.label)

        if let stringParameter = parameter as? StringParameter {
            stringParameter.value = value
        } else {
            throw FabricIntentError.unsupportedParameterType(parameterEntity.label)
        }

        return try self.persistParameterUpdate(graph: loadedGraph, publishedPort: publishedPort, label: parameterEntity.label)
    }

    func setPublishedVector(_ parameterEntity: FabricPublishedParameterEntity, components: [Double]) throws -> FabricPublishedParameterEntity {
        let loadedGraph = try self.loadGraph(forGraphURL: parameterEntity.graphURL)
        let publishedPort = try self.publishedPort(withIdentifier: parameterEntity.publishedPortIdentifier, in: loadedGraph.graph)
        let parameter = try self.parameter(forPublishedPort: publishedPort, label: parameterEntity.label)

        if let float2Parameter = parameter as? Float2Parameter {
            guard components.count == 2 else {
                throw FabricIntentError.invalidValue("Expected 2 components")
            }
            float2Parameter.value = simd_float2(Float(components[0]), Float(components[1]))
        } else if let float3Parameter = parameter as? Float3Parameter {
            guard components.count == 3 else {
                throw FabricIntentError.invalidValue("Expected 3 components")
            }
            float3Parameter.value = simd_float3(Float(components[0]), Float(components[1]), Float(components[2]))
        } else if let float4Parameter = parameter as? Float4Parameter {
            guard components.count == 4 else {
                throw FabricIntentError.invalidValue("Expected 4 components")
            }
            float4Parameter.value = simd_float4(Float(components[0]), Float(components[1]), Float(components[2]), Float(components[3]))
        } else {
            throw FabricIntentError.unsupportedParameterType(parameterEntity.label)
        }

        return try self.persistParameterUpdate(graph: loadedGraph, publishedPort: publishedPort, label: parameterEntity.label)
    }

    private func persistParameterUpdate(
        graph loadedGraph: LoadedGraph,
        publishedPort: Fabric.Port,
        label: String
    ) throws -> FabricPublishedParameterEntity {
        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.persistGraph(loadedGraph)
        let refreshedPort = try self.publishedPort(withIdentifier: publishedPort.id.uuidString, in: loadedGraph.graph)
        guard let refreshedParameter = refreshedPort.parameter else {
            throw FabricIntentError.unsupportedParameterType(label)
        }
        return self.makePublishedParameterEntity(parameter: refreshedParameter, port: refreshedPort, graphURL: loadedGraph.graphURL)
    }

    private func publishedParameters(in graph: Graph, graphURL: String) -> [FabricPublishedParameterEntity] {
        graph.getPublishedPorts().compactMap { port in
            guard let parameter = port.parameter else { return nil }
            return self.makePublishedParameterEntity(parameter: parameter, port: port, graphURL: graphURL)
        }
    }

    private func loadGraph(for graphEntity: FabricGraphEntity) throws -> LoadedGraph {
        if let graph = self.untitledGraphs[graphEntity.graphIdentifier] {
            return LoadedGraph(fileURL: nil, graphURL: self.untitledGraphURL(for: graph.id), graph: graph)
        }
        return try self.loadGraph(forGraphURL: graphEntity.graphURL)
    }

    private func loadGraph(forGraphURL graphURL: String) throws -> LoadedGraph {
        if let untitledGraph = self.untitledGraph(for: graphURL) {
            return LoadedGraph(fileURL: nil, graphURL: graphURL, graph: untitledGraph)
        }
        let url = try self.graphURL(from: graphURL)
        return try self.loadGraph(at: url)
    }

    private func loadGraph(at url: URL) throws -> LoadedGraph {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: self.makeContext())
        let graph = try decoder.decode(Graph.self, from: data)
        return LoadedGraph(fileURL: url, graphURL: url.absoluteString, graph: graph)
    }

    private func persistGraph(_ loadedGraph: LoadedGraph) throws {
        if let fileURL = loadedGraph.fileURL {
            try self.saveGraph(loadedGraph.graph, to: fileURL)
        } else {
            self.untitledGraphs[loadedGraph.graph.id.uuidString] = loadedGraph.graph
        }
    }

    private func saveGraph(_ graph: Graph, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(graph)
        try data.write(to: url, options: [.atomic])
    }

    private func makeContext() -> Context {
        Context(
            device: MTLCreateSystemDefaultDevice()!,
            sampleCount: 1,
            colorPixelFormat: .rgba16Float,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .stencil8
        )
    }

    private func graphURL(from file: IntentFile) throws -> URL {
        guard let fileURL = file.fileURL else {
            throw FabricIntentError.invalidGraphFile
        }

        return try self.validateGraphURL(fileURL)
    }

    private func graphURL(from graphURLString: String) throws -> URL {
        let trimmedValue = graphURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw FabricIntentError.invalidGraphURL(graphURLString)
        }

        if let url = URL(string: trimmedValue), url.scheme != nil {
            return try self.validateGraphURL(url.standardizedFileURL)
        }

        return try self.validateGraphURL(URL(fileURLWithPath: trimmedValue).standardizedFileURL)
    }

    private func fileURL(for graphEntity: FabricGraphEntity) throws -> URL? {
        if self.untitledGraphs[graphEntity.graphIdentifier] != nil {
            return nil
        }
        return try self.graphURL(from: graphEntity.graphURL)
    }

    private func untitledGraphURL(for graphID: UUID) -> String {
        "\(self.untitledScheme)://\(graphID.uuidString)"
    }

    private func untitledGraph(for graphURL: String) -> Graph? {
        guard
            let url = URL(string: graphURL),
            url.scheme == self.untitledScheme,
            let host = url.host(percentEncoded: false) ?? url.host()
        else {
            return nil
        }

        return self.untitledGraphs[host]
    }

    private func defaultUntitledSaveURL() throws -> URL {
        let baseDirectory = URL.documentsDirectory
        let fileManager = FileManager.default
        var candidateURL = baseDirectory.appending(path: "Untitled.fabric")
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = baseDirectory.appending(path: "Untitled \(suffix).fabric")
            suffix += 1
        }

        return candidateURL
    }

    private func validateGraphURL(_ url: URL) throws -> URL {
        guard url.isFileURL else {
            throw FabricIntentError.invalidGraphURL(url.absoluteString)
        }
        guard url.pathExtension.localizedCaseInsensitiveCompare("fabric") == .orderedSame else {
            throw FabricIntentError.unsupportedGraphFile(url)
        }
        return url
    }

    private func node(withIdentifier nodeIdentifier: String, in graph: Graph) throws -> Node {
        guard let nodeUUID = UUID(uuidString: nodeIdentifier), let node = graph.node(forID: nodeUUID) else {
            throw FabricIntentError.nodeNotFound(nodeIdentifier)
        }
        return node
    }

    private func port(withIdentifier portIdentifier: String, in graph: Graph) throws -> Fabric.Port {
        guard let portUUID = UUID(uuidString: portIdentifier), let port = graph.nodePort(forID: portUUID) else {
            throw FabricIntentError.portNotFound(portIdentifier)
        }
        return port
    }

    private func publishedPort(withIdentifier portIdentifier: String, in graph: Graph) throws -> Fabric.Port {
        let port = try self.port(withIdentifier: portIdentifier, in: graph)
        guard port.published else {
            throw FabricIntentError.notAPublishedParameter(portIdentifier)
        }
        return port
    }

    private func parameter(forPublishedPort port: Fabric.Port, label: String) throws -> any Parameter {
        guard let parameter = port.parameter else {
            throw FabricIntentError.unsupportedParameterType(label)
        }
        return parameter
    }

    private func registryWrapper(for registryNode: FabricRegistryNodeEntity) throws -> NodeClassWrapper {
        guard let wrapper = NodeRegistry.shared.availableNodes.first(where: { node in
            node.nodeName == registryNode.nodeName &&
            String(describing: node.nodeClass) == registryNode.nodeClassName
        }) else {
            throw FabricIntentError.registryNodeNotFound(registryNode.nodeName)
        }

        return wrapper
    }

    private func makeGraphEntity(graph: Graph, fileURL: URL?) -> FabricGraphEntity {
        let publishedParameterCount = graph.getPublishedPorts().count
        return FabricGraphEntity(
            graphURL: fileURL?.absoluteString ?? self.untitledGraphURL(for: graph.id),
            displayName: fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled",
            graphIdentifier: graph.id.uuidString,
            nodeCount: graph.nodes.count,
            publishedParameterCount: publishedParameterCount
        )
    }

    private func makeNodeEntity(node: Node, graphURL: String) -> FabricNodeEntity {
        FabricNodeEntity(
            graphURL: graphURL,
            nodeIdentifier: node.id.uuidString,
            displayName: node.name,
            nodeClassName: String(describing: type(of: node)),
            nodeTypeDescription: node.nodeType.description
        )
    }

    private func makePortEntity(port: Fabric.Port, graphURL: String) -> FabricPortEntity {
        FabricPortEntity(
            graphURL: graphURL,
            nodeIdentifier: port.node?.id.uuidString ?? "",
            portIdentifier: port.id.uuidString,
            portName: port.name,
            portDisplayName: port.displayName,
            kind: port.kind.rawValue,
            portType: port.portType.rawValue,
            isPublished: port.published,
            connectionCount: port.connections.count
        )
    }

    private func makePublishedParameterEntity(
        parameter: any Parameter,
        port: Fabric.Port,
        graphURL: String
    ) -> FabricPublishedParameterEntity {
        FabricPublishedParameterEntity(
            graphURL: graphURL,
            parameterIdentifier: parameter.id.uuidString,
            publishedPortIdentifier: port.id.uuidString,
            label: port.displayName,
            valueSummary: self.parameterValueSummary(parameter),
            controlType: String(describing: type(of: parameter)),
            parameterType: port.portType.rawValue
        )
    }

    private func makeRegistryNodeEntity(wrapper: NodeClassWrapper) -> FabricRegistryNodeEntity {
        FabricRegistryNodeEntity(
            nodeName: wrapper.nodeName,
            nodeClassName: String(describing: wrapper.nodeClass),
            nodeTypeDescription: wrapper.nodeType.description,
            nodeDescription: wrapper.nodeDescription,
            sourcePath: wrapper.fileURL?.path
        )
    }

    private func parameterValueSummary(_ parameter: any Parameter) -> String {
        switch parameter {
        case let parameter as BoolParameter:
            return parameter.value.description
        case let parameter as IntParameter:
            return parameter.value.description
        case let parameter as FloatParameter:
            return parameter.value.formatted(.number.precision(.fractionLength(3)))
        case let parameter as DoubleParameter:
            return parameter.value.formatted(.number.precision(.fractionLength(3)))
        case let parameter as StringParameter:
            return parameter.value
        case let parameter as Float2Parameter:
            return [parameter.value.x, parameter.value.y]
                .map { $0.formatted(.number.precision(.fractionLength(3))) }
                .joined(separator: ", ")
        case let parameter as Float3Parameter:
            return [parameter.value.x, parameter.value.y, parameter.value.z]
                .map { $0.formatted(.number.precision(.fractionLength(3))) }
                .joined(separator: ", ")
        case let parameter as Float4Parameter:
            return [parameter.value.x, parameter.value.y, parameter.value.z, parameter.value.w]
                .map { $0.formatted(.number.precision(.fractionLength(3))) }
                .joined(separator: ", ")
        default:
            return parameter.description
        }
    }
}
