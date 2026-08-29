//
//  FabricAppIntents.swift
//  Fabric Editor
//
//  Created by Codex on 4/7/26.
//

import AppIntents
import Foundation

struct GetGraphFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Graph File"
    static let description = IntentDescription("Select a Fabric graph file and return it as a graph entity.")

    @Parameter(title: "Graph File")
    var graphFile: IntentFile

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.openGraph(file: self.graphFile)
        return .result(value: graph, dialog: "Loaded \(graph.displayName).")
    }
}

struct CreateNewGraphIntent: AppIntent {
    static let title: LocalizedStringResource = "Create New Graph"
    static let description = IntentDescription("Create a new untitled Fabric graph and return it as a graph entity.")

    @Parameter(title: "Use Template", default: true)
    var useTemplate: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = await FabricDocumentAutomationService.shared.createGraph(useTemplate: self.useTemplate)
        return .result(value: graph, dialog: "Created \(graph.displayName).")
    }
}

struct GetGraphDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Graph Details"
    static let description = IntentDescription("Refresh and return summary information about a Fabric graph.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let refreshedGraph = try await FabricDocumentAutomationService.shared.graphDetails(for: self.graph)
        return .result(
            value: refreshedGraph,
            dialog: "\(refreshedGraph.displayName) has \(refreshedGraph.nodeCount) nodes and \(refreshedGraph.publishedParameterCount) published parameters."
        )
    }
}

struct SaveGraphIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Graph"
    static let description = IntentDescription("Save graph changes back to disk.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let savedGraph = try await FabricDocumentAutomationService.shared.saveGraph(self.graph)
        return .result(value: savedGraph, dialog: "Saved \(savedGraph.displayName).")
    }
}

struct ExportGraphImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Graph Image"
    static let description = IntentDescription("Export a Fabric graph to an image file.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    @Parameter(title: "Destination Path")
    var destinationPath: String

    @Parameter(title: "Width", default: 1920)
    var width: Int

    @Parameter(title: "Height", default: 1080)
    var height: Int

    @Parameter(title: "Time", default: 0)
    var time: Double

    @Parameter(title: "Format", default: .png)
    var format: FabricImageExportFormatAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let file = try await FabricGraphExportAutomation.shared.exportImage(
            graph: self.graph,
            destinationPath: self.destinationPath,
            width: self.width,
            height: self.height,
            time: self.time,
            format: self.format
        )
        return .result(value: file, dialog: "Exported an image from \(self.graph.displayName).")
    }
}

struct ExportGraphMovieIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Graph Movie"
    static let description = IntentDescription("Export a Fabric graph to a movie file.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    @Parameter(title: "Destination Path")
    var destinationPath: String

    @Parameter(title: "Start Time", default: 0)
    var startTime: Double

    @Parameter(title: "Duration", default: 5)
    var duration: Double

    @Parameter(title: "Width", default: 1920)
    var width: Int

    @Parameter(title: "Height", default: 1080)
    var height: Int

    @Parameter(title: "Frame Rate", default: 30)
    var frameRate: Double

    @Parameter(title: "Codec", default: .h264)
    var codec: FabricMovieExportCodecAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let file = try await FabricGraphExportAutomation.shared.exportMovie(
            graph: self.graph,
            destinationPath: self.destinationPath,
            startTime: self.startTime,
            duration: self.duration,
            width: self.width,
            height: self.height,
            frameRate: self.frameRate,
            codec: self.codec
        )
        return .result(value: file, dialog: "Exported a movie from \(self.graph.displayName).")
    }
}

struct RevealGraphFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Reveal Graph File"
    static let description = IntentDescription("Reveal a graph file in Finder.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let file = try await FabricDocumentAutomationService.shared.revealGraphFile(for: self.graph)
        return .result(value: file, dialog: "Revealed \(self.graph.displayName).")
    }
}

struct ListAvailableNodesIntent: AppIntent {
    static let title: LocalizedStringResource = "List Available Nodes"
    static let description = IntentDescription("Return all node types available in Fabric’s node registry.")

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricRegistryNodeEntity]> & ProvidesDialog {
        let nodes = await FabricDocumentAutomationService.shared.listRegistryNodes()
        return .result(value: nodes, dialog: "Found \(nodes.count) available nodes.")
    }
}

struct FindAvailableNodesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Available Nodes"
    static let description = IntentDescription("Search the Fabric node registry by name, type, or description.")

    @Parameter(title: "Search Text")
    var searchText: String

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricRegistryNodeEntity]> & ProvidesDialog {
        let nodes = await FabricDocumentAutomationService.shared.listRegistryNodes(matching: self.searchText)
        return .result(value: nodes, dialog: "Found \(nodes.count) matching node types.")
    }
}

struct GetAvailableNodeDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Available Node Details"
    static let description = IntentDescription("Return the canonical details for a registry node type.")

    @Parameter(title: "Registry Node")
    var registryNode: FabricRegistryNodeEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricRegistryNodeEntity> & ProvidesDialog {
        let registryNode = try await FabricDocumentAutomationService.shared.registryNodeDetails(for: self.registryNode)
        return .result(value: registryNode, dialog: "Loaded \(registryNode.nodeName).")
    }
}

struct GetGraphNodesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Graph Nodes"
    static let description = IntentDescription("Return all nodes currently in a graph.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricNodeEntity]> & ProvidesDialog {
        let nodes = try await FabricDocumentAutomationService.shared.listNodes(in: self.graph)
        return .result(value: nodes, dialog: "Found \(nodes.count) nodes.")
    }
}

struct FindGraphNodesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Graph Nodes"
    static let description = IntentDescription("Search nodes inside a graph by name, class, or type.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    @Parameter(title: "Search Text")
    var searchText: String

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricNodeEntity]> & ProvidesDialog {
        let nodes = try await FabricDocumentAutomationService.shared.findNodes(in: self.graph, matching: self.searchText)
        return .result(value: nodes, dialog: "Found \(nodes.count) matching nodes.")
    }
}

struct GetNodeDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Node Details"
    static let description = IntentDescription("Return detailed information about a graph node.")

    @Parameter(title: "Node")
    var node: FabricNodeEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricNodeEntity> & ProvidesDialog {
        let node = try await FabricDocumentAutomationService.shared.nodeDetails(for: self.node)
        return .result(value: node, dialog: "Loaded \(node.displayName).")
    }
}

struct GetNodePortsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Node Ports"
    static let description = IntentDescription("Return all ports on a graph node.")

    @Parameter(title: "Node")
    var node: FabricNodeEntity

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricPortEntity]> & ProvidesDialog {
        let ports = try await FabricDocumentAutomationService.shared.listPorts(for: self.node)
        return .result(value: ports, dialog: "Found \(ports.count) ports.")
    }
}

struct FindNodePortsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Node Ports"
    static let description = IntentDescription("Search a node’s ports by name, type, or publication state.")

    @Parameter(title: "Node")
    var node: FabricNodeEntity

    @Parameter(title: "Search Text", default: "")
    var searchText: String

    @Parameter(title: "Kind")
    var kind: FabricPortKindAppEnum?

    @Parameter(title: "Published Only", default: false)
    var publishedOnly: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricPortEntity]> & ProvidesDialog {
        let ports = try await FabricDocumentAutomationService.shared.findPorts(
            for: self.node,
            matching: self.searchText,
            kind: self.kind,
            publishedOnly: self.publishedOnly
        )
        return .result(value: ports, dialog: "Found \(ports.count) matching ports.")
    }
}

struct GetGraphPublishedParametersIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Graph Published Parameters"
    static let description = IntentDescription("Return the graph’s published parameter surface.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricPublishedParameterEntity]> & ProvidesDialog {
        let parameters = try await FabricDocumentAutomationService.shared.listPublishedParameters(in: self.graph)
        return .result(value: parameters, dialog: "Found \(parameters.count) published parameters.")
    }
}

struct FindPublishedParametersIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Published Parameters"
    static let description = IntentDescription("Search published graph parameters by label, type, or value summary.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    @Parameter(title: "Search Text")
    var searchText: String

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricPublishedParameterEntity]> & ProvidesDialog {
        let parameters = try await FabricDocumentAutomationService.shared.findPublishedParameters(in: self.graph, matching: self.searchText)
        return .result(value: parameters, dialog: "Found \(parameters.count) matching published parameters.")
    }
}

struct GetPublishedParameterDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Published Parameter Details"
    static let description = IntentDescription("Return the canonical details for a published parameter.")

    @Parameter(title: "Published Parameter")
    var parameter: FabricPublishedParameterEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricPublishedParameterEntity> & ProvidesDialog {
        let parameter = try await FabricDocumentAutomationService.shared.publishedParameterDetails(for: self.parameter)
        return .result(value: parameter, dialog: "Loaded \(parameter.label).")
    }
}

struct AddNodeToGraphIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Node To Graph"
    static let description = IntentDescription("Add a registry node type to a graph and return the created node.")

    @Parameter(title: "Graph")
    var graph: FabricGraphEntity

    @Parameter(title: "Registry Node")
    var registryNode: FabricRegistryNodeEntity

    @Parameter(title: "X Position")
    var xPosition: Double?

    @Parameter(title: "Y Position")
    var yPosition: Double?

    func perform() async throws -> some IntentResult & ReturnsValue<FabricNodeEntity> & ProvidesDialog {
        let node = try await FabricDocumentAutomationService.shared.addNode(
            registryNode: self.registryNode,
            to: self.graph,
            x: self.xPosition,
            y: self.yPosition
        )
        return .result(value: node, dialog: "Added \(node.displayName).")
    }
}

struct RemoveNodeFromGraphIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Node From Graph"
    static let description = IntentDescription("Remove a node from a graph.")

    @Parameter(title: "Node")
    var node: FabricNodeEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.removeNode(self.node)
        return .result(value: graph, dialog: "Removed \(self.node.displayName).")
    }
}

struct ConnectPortsIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect Ports"
    static let description = IntentDescription("Connect one outlet port to one inlet port.")

    @Parameter(title: "Source Port")
    var sourcePort: FabricPortEntity

    @Parameter(title: "Destination Port")
    var destinationPort: FabricPortEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.connectPorts(from: self.sourcePort, to: self.destinationPort)
        return .result(value: graph, dialog: "Connected \(self.sourcePort.portDisplayName) to \(self.destinationPort.portDisplayName).")
    }
}

struct DisconnectPortsIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnect Ports"
    static let description = IntentDescription("Disconnect a specific connection or all connections from a source port.")

    @Parameter(title: "Source Port")
    var sourcePort: FabricPortEntity

    @Parameter(title: "Destination Port")
    var destinationPort: FabricPortEntity?

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.disconnectPorts(from: self.sourcePort, to: self.destinationPort)
        return .result(value: graph, dialog: "Updated connections for \(self.sourcePort.portDisplayName).")
    }
}

struct PublishPortIntent: AppIntent {
    static let title: LocalizedStringResource = "Publish Port"
    static let description = IntentDescription("Expose a node port on the graph’s published control surface.")

    @Parameter(title: "Port")
    var port: FabricPortEntity

    @Parameter(title: "Published Label")
    var publishedLabel: String?

    func perform() async throws -> some IntentResult & ReturnsValue<FabricPublishedParameterEntity> & ProvidesDialog {
        let parameter = try await FabricDocumentAutomationService.shared.publishPort(self.port, label: self.publishedLabel)
        return .result(value: parameter, dialog: "Published \(parameter.label).")
    }
}

struct UnpublishPortIntent: AppIntent {
    static let title: LocalizedStringResource = "Unpublish Port"
    static let description = IntentDescription("Remove a node port from the graph’s published control surface.")

    @Parameter(title: "Port")
    var port: FabricPortEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.unpublishPort(self.port)
        return .result(value: graph, dialog: "Unpublished \(self.port.portDisplayName).")
    }
}

struct UnpublishPublishedParameterIntent: AppIntent {
    static let title: LocalizedStringResource = "Unpublish Published Parameter"
    static let description = IntentDescription("Remove a published parameter from the graph’s control surface.")

    @Parameter(title: "Published Parameter")
    var parameter: FabricPublishedParameterEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.unpublishParameter(self.parameter)
        return .result(value: graph, dialog: "Unpublished \(self.parameter.label).")
    }
}

struct SetPublishedBooleanIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Published Boolean"
    static let description = IntentDescription("Set a published Boolean parameter.")

    @Parameter(title: "Published Parameter")
    var parameter: FabricPublishedParameterEntity

    @Parameter(title: "Value")
    var value: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.setPublishedBoolean(self.parameter, value: self.value)
        return .result(value: graph, dialog: "Set \(self.parameter.label) to \(self.value ? "on" : "off").")
    }
}

struct SetPublishedNumberIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Published Number"
    static let description = IntentDescription("Set a published numeric parameter.")

    @Parameter(title: "Published Parameter")
    var parameter: FabricPublishedParameterEntity

    @Parameter(title: "Value")
    var value: Double

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.setPublishedNumber(self.parameter, value: self.value)
        return .result(value: graph, dialog: "Set \(self.parameter.label) to \(self.value.formatted()).")
    }
}

struct SetPublishedIntegerIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Published Integer"
    static let description = IntentDescription("Set a published integer parameter.")

    @Parameter(title: "Published Parameter")
    var parameter: FabricPublishedParameterEntity

    @Parameter(title: "Value")
    var value: Int

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.setPublishedInteger(self.parameter, value: self.value)
        return .result(value: graph, dialog: "Set \(self.parameter.label) to \(self.value).")
    }
}

struct SetPublishedTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Published Text"
    static let description = IntentDescription("Set a published text parameter.")

    @Parameter(title: "Published Parameter")
    var parameter: FabricPublishedParameterEntity

    @Parameter(title: "Value")
    var value: String

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.setPublishedText(self.parameter, value: self.value)
        return .result(value: graph, dialog: "Updated \(self.parameter.label).")
    }
}

struct SetPublishedVectorIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Published Vector"
    static let description = IntentDescription("Set a published vector or color parameter using numeric components.")

    @Parameter(title: "Published Parameter")
    var parameter: FabricPublishedParameterEntity

    @Parameter(title: "Components")
    var components: [Double]

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.setPublishedVector(self.parameter, components: self.components)
        return .result(value: graph, dialog: "Updated \(self.parameter.label).")
    }
}

struct FabricEditorShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetGraphFileIntent(),
            phrases: [
                "Get a Fabric graph in \(.applicationName)",
                "Open a graph with \(.applicationName)",
            ],
            shortTitle: "Get Graph",
            systemImageName: "folder"
        )

        AppShortcut(
            intent: GetGraphPublishedParametersIntent(),
            phrases: [
                "Get graph controls in \(.applicationName)",
                "List published parameters in \(.applicationName)",
            ],
            shortTitle: "Published Parameters",
            systemImageName: "slider.horizontal.3"
        )

        AppShortcut(
            intent: SetPublishedNumberIntent(),
            phrases: [
                "Set a Fabric graph control in \(.applicationName)",
            ],
            shortTitle: "Set Number",
            systemImageName: "dial.medium"
        )

        AppShortcut(
            intent: ExportGraphImageIntent(),
            phrases: [
                "Export a Fabric image with \(.applicationName)",
                "Render a graph image in \(.applicationName)",
            ],
            shortTitle: "Export Image",
            systemImageName: "photo"
        )

        AppShortcut(
            intent: ExportGraphMovieIntent(),
            phrases: [
                "Export a Fabric movie with \(.applicationName)",
                "Render a graph movie in \(.applicationName)",
            ],
            shortTitle: "Export Movie",
            systemImageName: "film"
        )
    }
}
