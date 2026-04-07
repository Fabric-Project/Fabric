//
//  FabricDocumentAutomationService.swift
//  Fabric Editor
//
//  Created by Codex on 4/7/26.
//

import AppKit
import Foundation
import Metal
import Fabric
import Satin
import simd

enum FabricIntentError: LocalizedError {
    case invalidGraphURL(String)
    case unsupportedGraphFile(URL)
    case fileAlreadyExists(URL)
    case nodeNotFound(String)
    case portNotFound(String)
    case notAPublishedParameter(String)
    case ambiguousPublishedParameter(String)
    case unsupportedParameterType(String)
    case invalidValue(String)
    case incompatiblePorts(String)
    case registryNodeNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidGraphURL(let value):
            return "Invalid graph URL: \(value)"
        case .unsupportedGraphFile(let url):
            return "Unsupported graph file: \(url.path)"
        case .fileAlreadyExists(let url):
            return "A graph already exists at \(url.path)"
        case .nodeNotFound(let nodeID):
            return "Node not found: \(nodeID)"
        case .portNotFound(let portID):
            return "Port not found: \(portID)"
        case .notAPublishedParameter(let label):
            return "Published parameter not found: \(label)"
        case .ambiguousPublishedParameter(let label):
            return "Multiple published parameters match '\(label)'"
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

@MainActor
final class FabricDocumentAutomationService {
    static let shared = FabricDocumentAutomationService()

    private init() {}

    struct LoadedGraph {
        let url: URL
        let graph: Graph
    }

    func createGraph(at graphURLString: String, useTemplate: Bool) throws -> FabricGraphEntity {
        let url = try self.graphURL(from: graphURLString)
        guard url.isFileURL else {
            throw FabricIntentError.invalidGraphURL(graphURLString)
        }
        guard url.pathExtension.localizedCaseInsensitiveCompare("fabric") == .orderedSame else {
            throw FabricIntentError.unsupportedGraphFile(url)
        }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FabricIntentError.fileAlreadyExists(url)
        }

        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true, attributes: nil)

        let document = useTemplate ? FabricDocument(withTemplate: true) : FabricDocument()
        try self.saveGraph(document.editingContext.rootGraph, to: url)
        NSWorkspace.shared.open(url)
        return self.makeGraphEntity(graph: document.editingContext.rootGraph, url: url)
    }

    func openGraph(at graphURLString: String) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(at: graphURLString)
        NSWorkspace.shared.open(loadedGraph.url)
        return self.makeGraphEntity(graph: loadedGraph.graph, url: loadedGraph.url)
    }

    func graphSummary(for graphURLString: String) throws -> String {
        let loadedGraph = try self.loadGraph(at: graphURLString)
        let graph = loadedGraph.graph
        let publishedCount = graph.getPublishedPorts().count
        return "\(graph.nodes.count) nodes, \(publishedCount) published ports"
    }

    func graphEntity(for graphURLString: String) throws -> FabricGraphEntity {
        let loadedGraph = try self.loadGraph(at: graphURLString)
        return self.makeGraphEntity(graph: loadedGraph.graph, url: loadedGraph.url)
    }

    func listNodes(in graphURLString: String) throws -> [FabricNodeEntity] {
        let loadedGraph = try self.loadGraph(at: graphURLString)
        return loadedGraph.graph.nodes.map { self.makeNodeEntity(node: $0, graphURL: loadedGraph.url.absoluteString) }
    }

    func listPublishedParameters(in graphURLString: String) throws -> [FabricPublishedParameterEntity] {
        let loadedGraph = try self.loadGraph(at: graphURLString)
        return loadedGraph.graph
            .getPublishedPorts()
            .compactMap { port in
                guard let parameter = port.parameter else { return nil }
                return self.makePublishedParameterEntity(
                    parameter: parameter,
                    port: port,
                    graphURL: loadedGraph.url.absoluteString
                )
            }
    }

    func listRegistryNodes(matching searchText: String?) -> [FabricRegistryNodeEntity] {
        let normalizedSearchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NodeRegistry.shared.availableNodes.compactMap { wrapper in
            if let normalizedSearchText, !normalizedSearchText.isEmpty {
                let haystack = [
                    wrapper.nodeName,
                    String(describing: wrapper.nodeClass),
                    wrapper.nodeType.description,
                    wrapper.nodeDescription,
                ]
                let matches = haystack.contains { $0.localizedStandardContains(normalizedSearchText) }
                if !matches {
                    return nil
                }
            }

            return self.makeRegistryNodeEntity(wrapper: wrapper)
        }
    }

    func nodeDetails(for nodeEntity: FabricNodeEntity) throws -> FabricNodeEntity {
        let loadedGraph = try self.loadGraph(at: nodeEntity.graphURL)
        let node = try self.node(withIdentifier: nodeEntity.nodeIdentifier, in: loadedGraph.graph)
        return self.makeNodeEntity(node: node, graphURL: loadedGraph.url.absoluteString)
    }

    func ports(for nodeEntity: FabricNodeEntity) throws -> [FabricPortEntity] {
        let loadedGraph = try self.loadGraph(at: nodeEntity.graphURL)
        let node = try self.node(withIdentifier: nodeEntity.nodeIdentifier, in: loadedGraph.graph)
        return node.ports.map { self.makePortEntity(port: $0, graphURL: loadedGraph.url.absoluteString) }
    }

    func addNode(
        registryNode: FabricRegistryNodeEntity,
        to graphURLString: String,
        x: Double?,
        y: Double?
    ) throws -> FabricNodeEntity {
        let loadedGraph = try self.loadGraph(at: graphURLString)
        let wrapper = try self.registryWrapper(for: registryNode)
        let node = try wrapper.initializeNode(context: loadedGraph.graph.context)

        if let x, let y {
            node.offset = CGSize(width: x, height: y)
        }

        loadedGraph.graph.addNode(node)
        try self.saveGraph(loadedGraph.graph, to: loadedGraph.url)
        return self.makeNodeEntity(node: node, graphURL: loadedGraph.url.absoluteString)
    }

    func connectPorts(from sourcePort: FabricPortEntity, to destinationPort: FabricPortEntity) throws -> String {
        guard sourcePort.graphURL == destinationPort.graphURL else {
            throw FabricIntentError.incompatiblePorts("Ports must belong to the same graph")
        }

        let loadedGraph = try self.loadGraph(at: sourcePort.graphURL)
        let source = try self.port(withIdentifier: sourcePort.portIdentifier, in: loadedGraph.graph)
        let destination = try self.port(withIdentifier: destinationPort.portIdentifier, in: loadedGraph.graph)

        guard source.kind == .Outlet, destination.kind == .Inlet else {
            throw FabricIntentError.incompatiblePorts("Connect an outlet source to an inlet destination")
        }

        if !source.canConnect(to: destination) {
            throw FabricIntentError.incompatiblePorts("\(source.displayName) cannot connect to \(destination.displayName)")
        }

        source.connect(to: destination)
        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.saveGraph(loadedGraph.graph, to: loadedGraph.url)

        return "Connected \(source.displayName) to \(destination.displayName)"
    }

    func disconnectPorts(from sourcePort: FabricPortEntity, to destinationPort: FabricPortEntity?) throws -> String {
        let loadedGraph = try self.loadGraph(at: sourcePort.graphURL)
        let source = try self.port(withIdentifier: sourcePort.portIdentifier, in: loadedGraph.graph)

        if let destinationPort {
            let destination = try self.port(withIdentifier: destinationPort.portIdentifier, in: loadedGraph.graph)
            source.disconnect(from: destination)
        } else {
            source.disconnectAll()
        }

        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.saveGraph(loadedGraph.graph, to: loadedGraph.url)

        return destinationPort == nil
            ? "Disconnected all connections from \(source.displayName)"
            : "Disconnected \(source.displayName)"
    }

    func setPublishedParameters(_ assignments: [String], in graphURLString: String) throws -> [FabricPublishedParameterEntity] {
        let loadedGraph = try self.loadGraph(at: graphURLString)

        for assignment in assignments {
            let trimmedAssignment = assignment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAssignment.isEmpty {
                continue
            }

            let pair = try self.parseAssignment(trimmedAssignment)
            let port = try self.publishedPort(label: pair.label, in: loadedGraph.graph)
            let parameter = try self.parameter(forPublishedPort: port, label: pair.label)
            try self.apply(rawValue: pair.value, to: parameter, label: pair.label)
        }

        loadedGraph.graph.rebuildPublishedParameterGroup()
        try self.saveGraph(loadedGraph.graph, to: loadedGraph.url)
        return try self.listPublishedParameters(in: loadedGraph.url.absoluteString)
    }

    private func loadGraph(at graphURLString: String) throws -> LoadedGraph {
        let url = try self.graphURL(from: graphURLString)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: self.makeContext())
        let graph = try decoder.decode(Graph.self, from: data)
        return LoadedGraph(url: url, graph: graph)
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

    private func graphURL(from graphURLString: String) throws -> URL {
        let trimmedValue = graphURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw FabricIntentError.invalidGraphURL(graphURLString)
        }

        if let url = URL(string: trimmedValue), url.scheme != nil {
            return url.standardizedFileURL
        }

        return URL(fileURLWithPath: trimmedValue).standardizedFileURL
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

    private func publishedPort(label: String, in graph: Graph) throws -> Fabric.Port {
        let matches = graph
            .getPublishedPorts()
            .filter { $0.displayName.localizedStandardContains(label) || $0.displayName == label || $0.name == label }

        if matches.isEmpty {
            throw FabricIntentError.notAPublishedParameter(label)
        }

        if matches.count > 1 {
            let exactMatches = matches.filter { $0.displayName == label || $0.name == label }
            if exactMatches.count == 1, let exactMatch = exactMatches.first {
                return exactMatch
            }
            throw FabricIntentError.ambiguousPublishedParameter(label)
        }

        guard let match = matches.first else {
            throw FabricIntentError.notAPublishedParameter(label)
        }

        return match
    }

    private func parameter(forPublishedPort port: Fabric.Port, label: String) throws -> any Parameter {
        guard let parameter = port.parameter else {
            throw FabricIntentError.unsupportedParameterType(label)
        }
        return parameter
    }

    private func parseAssignment(_ assignment: String) throws -> (label: String, value: String) {
        guard let delimiterIndex = assignment.firstIndex(of: "=") else {
            throw FabricIntentError.invalidValue("Use Label=Value format")
        }

        let label = String(assignment[..<delimiterIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let valueStartIndex = assignment.index(after: delimiterIndex)
        let value = String(assignment[valueStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !label.isEmpty else {
            throw FabricIntentError.invalidValue("Missing parameter label")
        }

        return (label, value)
    }

    private func parseFloatComponents(_ rawValue: String, expectedCount: Int) throws -> [Float] {
        let components = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard components.count == expectedCount else {
            throw FabricIntentError.invalidValue("Expected \(expectedCount) comma-separated values")
        }

        let numbers = try components.map { component -> Float in
            guard let value = Float(component) else {
                throw FabricIntentError.invalidValue("'\(component)' is not a number")
            }
            return value
        }

        return numbers
    }

    private func apply(rawValue: String, to parameter: any Parameter, label: String) throws {
        if let parameter = parameter as? BoolParameter {
            guard let value = Bool(rawValue) else {
                throw FabricIntentError.invalidValue("'\(rawValue)' is not a Bool")
            }
            parameter.value = value
            return
        }

        if let parameter = parameter as? GenericParameter<Bool> {
            guard let value = Bool(rawValue) else {
                throw FabricIntentError.invalidValue("'\(rawValue)' is not a Bool")
            }
            parameter.value = value
            return
        }

        if let parameter = parameter as? IntParameter {
            guard let value = Int(rawValue) else {
                throw FabricIntentError.invalidValue("'\(rawValue)' is not an Int")
            }
            parameter.value = value
            return
        }

        if let parameter = parameter as? GenericParameter<Int> {
            guard let value = Int(rawValue) else {
                throw FabricIntentError.invalidValue("'\(rawValue)' is not an Int")
            }
            parameter.value = value
            return
        }

        if let parameter = parameter as? FloatParameter {
            guard let value = Float(rawValue) else {
                throw FabricIntentError.invalidValue("'\(rawValue)' is not a Float")
            }
            parameter.value = value
            return
        }

        if let parameter = parameter as? GenericParameter<Float> {
            guard let value = Float(rawValue) else {
                throw FabricIntentError.invalidValue("'\(rawValue)' is not a Float")
            }
            parameter.value = value
            return
        }

        if let parameter = parameter as? StringParameter {
            parameter.value = rawValue
            return
        }

        if let parameter = parameter as? GenericParameter<String> {
            parameter.value = rawValue
            return
        }

        if let parameter = parameter as? Float2Parameter {
            let values = try self.parseFloatComponents(rawValue, expectedCount: 2)
            parameter.value = simd_float2(values[0], values[1])
            return
        }

        if let parameter = parameter as? GenericParameter<simd_float2> {
            let values = try self.parseFloatComponents(rawValue, expectedCount: 2)
            parameter.value = simd_float2(values[0], values[1])
            return
        }

        if let parameter = parameter as? Float3Parameter {
            let values = try self.parseFloatComponents(rawValue, expectedCount: 3)
            parameter.value = simd_float3(values[0], values[1], values[2])
            return
        }

        if let parameter = parameter as? GenericParameter<simd_float3> {
            let values = try self.parseFloatComponents(rawValue, expectedCount: 3)
            parameter.value = simd_float3(values[0], values[1], values[2])
            return
        }

        if let parameter = parameter as? Float4Parameter {
            let values = try self.parseFloatComponents(rawValue, expectedCount: 4)
            parameter.value = simd_float4(values[0], values[1], values[2], values[3])
            return
        }

        if let parameter = parameter as? GenericParameter<simd_float4> {
            let values = try self.parseFloatComponents(rawValue, expectedCount: 4)
            parameter.value = simd_float4(values[0], values[1], values[2], values[3])
            return
        }

        throw FabricIntentError.unsupportedParameterType(label)
    }

    private func registryWrapper(for entity: FabricRegistryNodeEntity) throws -> NodeClassWrapper {
        let matchingWrapper = NodeRegistry.shared.availableNodes.first { wrapper in
            String(describing: wrapper.nodeClass) == entity.nodeClassName
                && wrapper.nodeName == entity.nodeName
                && wrapper.fileURL?.path == entity.sourcePath
        }

        guard let matchingWrapper else {
            throw FabricIntentError.registryNodeNotFound(entity.nodeName)
        }

        return matchingWrapper
    }

    private func makeGraphEntity(graph: Graph, url: URL) -> FabricGraphEntity {
        let displayName = url.deletingPathExtension().lastPathComponent
        return FabricGraphEntity(
            graphURL: url.absoluteString,
            displayName: displayName,
            graphIdentifier: graph.id.uuidString
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
            portType: port.portType.rawValue
        )
    }

    private func makePublishedParameterEntity(parameter: any Parameter, port: Fabric.Port, graphURL: String) -> FabricPublishedParameterEntity {
        FabricPublishedParameterEntity(
            graphURL: graphURL,
            parameterIdentifier: parameter.id.uuidString,
            publishedPortIdentifier: port.id.uuidString,
            label: port.displayName,
            valueSummary: self.parameterValueSummary(parameter),
            controlType: parameter.controlType.rawValue,
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
        if let parameter = parameter as? BoolParameter {
            return String(parameter.value)
        }

        if let parameter = parameter as? GenericParameter<Bool> {
            return String(parameter.value)
        }

        if let parameter = parameter as? IntParameter {
            return String(parameter.value)
        }

        if let parameter = parameter as? GenericParameter<Int> {
            return String(parameter.value)
        }

        if let parameter = parameter as? FloatParameter {
            return String(parameter.value)
        }

        if let parameter = parameter as? GenericParameter<Float> {
            return String(parameter.value)
        }

        if let parameter = parameter as? StringParameter {
            return parameter.value
        }

        if let parameter = parameter as? GenericParameter<String> {
            return parameter.value
        }

        if let parameter = parameter as? Float2Parameter {
            return "\(parameter.value.x), \(parameter.value.y)"
        }

        if let parameter = parameter as? GenericParameter<simd_float2> {
            return "\(parameter.value.x), \(parameter.value.y)"
        }

        if let parameter = parameter as? Float3Parameter {
            return "\(parameter.value.x), \(parameter.value.y), \(parameter.value.z)"
        }

        if let parameter = parameter as? GenericParameter<simd_float3> {
            return "\(parameter.value.x), \(parameter.value.y), \(parameter.value.z)"
        }

        if let parameter = parameter as? Float4Parameter {
            return "\(parameter.value.x), \(parameter.value.y), \(parameter.value.z), \(parameter.value.w)"
        }

        if let parameter = parameter as? GenericParameter<simd_float4> {
            return "\(parameter.value.x), \(parameter.value.y), \(parameter.value.z), \(parameter.value.w)"
        }

        return parameter.debugDescription
    }
}
