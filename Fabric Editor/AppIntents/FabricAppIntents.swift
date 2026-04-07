//
//  FabricAppIntents.swift
//  Fabric Editor
//
//  Created by Codex on 4/7/26.
//

import AppIntents
import Foundation

struct OpenGraphIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Graph"
    static let description = IntentDescription("Open a Fabric graph from a file URL or path.")

    @Parameter(title: "Graph URL")
    var graphURL: String

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.openGraph(at: self.graphURL)
        return .result(value: graph, dialog: "Opened \(graph.displayName).")
    }
}

struct CreateGraphIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Graph"
    static let description = IntentDescription("Create a new Fabric graph file, optionally seeded with the default template.")

    @Parameter(title: "Graph URL")
    var graphURL: String

    @Parameter(title: "Use Template", default: true)
    var useTemplate: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<FabricGraphEntity> & ProvidesDialog {
        let graph = try await FabricDocumentAutomationService.shared.createGraph(at: self.graphURL, useTemplate: self.useTemplate)
        return .result(value: graph, dialog: "Created \(graph.displayName).")
    }
}

struct GetGraphSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Graph Summary"
    static let description = IntentDescription("Summarize a Fabric graph file.")

    @Parameter(title: "Graph URL")
    var graphURL: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = try await FabricDocumentAutomationService.shared.graphSummary(for: self.graphURL)
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct ListPublishedParametersIntent: AppIntent {
    static let title: LocalizedStringResource = "List Published Parameters"
    static let description = IntentDescription("Return the published parameter surface for a graph.")

    @Parameter(title: "Graph URL")
    var graphURL: String

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricPublishedParameterEntity]> & ProvidesDialog {
        let parameters = try await FabricDocumentAutomationService.shared.listPublishedParameters(in: self.graphURL)
        return .result(value: parameters, dialog: "Found \(parameters.count) published parameters.")
    }
}

struct SetPublishedParametersIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Published Parameters"
    static let description = IntentDescription("Apply one or more published parameter assignments using Label=Value entries.")

    @Parameter(title: "Graph URL")
    var graphURL: String

    @Parameter(title: "Assignments")
    var assignments: [String]

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricPublishedParameterEntity]> & ProvidesDialog {
        let parameters = try await FabricDocumentAutomationService.shared.setPublishedParameters(self.assignments, in: self.graphURL)
        return .result(value: parameters, dialog: "Updated \(self.assignments.count) parameter assignments.")
    }
}

struct ListNodesIntent: AppIntent {
    static let title: LocalizedStringResource = "List Nodes"
    static let description = IntentDescription("List nodes in a Fabric graph.")

    @Parameter(title: "Graph URL")
    var graphURL: String

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricNodeEntity]> & ProvidesDialog {
        let nodes = try await FabricDocumentAutomationService.shared.listNodes(in: self.graphURL)
        return .result(value: nodes, dialog: "Found \(nodes.count) nodes.")
    }
}

struct ListNodeRegistryIntent: AppIntent {
    static let title: LocalizedStringResource = "List Node Registry"
    static let description = IntentDescription("List all available node registry entries.")

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricRegistryNodeEntity]> & ProvidesDialog {
        let nodes = await FabricDocumentAutomationService.shared.listRegistryNodes(matching: nil)
        return .result(value: nodes, dialog: "Found \(nodes.count) registry nodes.")
    }
}

struct SearchNodeRegistryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Node Registry"
    static let description = IntentDescription("Search available Fabric node registry entries.")

    @Parameter(title: "Search Text")
    var searchText: String

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricRegistryNodeEntity]> & ProvidesDialog {
        let nodes = await FabricDocumentAutomationService.shared.listRegistryNodes(matching: self.searchText)
        return .result(value: nodes, dialog: "Found \(nodes.count) matching registry nodes.")
    }
}

struct AddNodeToGraphIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Node To Graph"
    static let description = IntentDescription("Add a registry node to a graph file.")

    @Parameter(title: "Graph URL")
    var graphURL: String

    @Parameter(title: "Registry Node")
    var registryNode: FabricRegistryNodeEntity

    @Parameter(title: "X Position")
    var xPosition: Double?

    @Parameter(title: "Y Position")
    var yPosition: Double?

    func perform() async throws -> some IntentResult & ReturnsValue<FabricNodeEntity> & ProvidesDialog {
        let node = try await FabricDocumentAutomationService.shared.addNode(
            registryNode: self.registryNode,
            to: self.graphURL,
            x: self.xPosition,
            y: self.yPosition
        )
        return .result(value: node, dialog: "Added \(node.displayName).")
    }
}

struct GetNodeDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Node Details"
    static let description = IntentDescription("Return the canonical node details for a node reference.")

    @Parameter(title: "Node")
    var node: FabricNodeEntity

    func perform() async throws -> some IntentResult & ReturnsValue<FabricNodeEntity> & ProvidesDialog {
        let node = try await FabricDocumentAutomationService.shared.nodeDetails(for: self.node)
        return .result(value: node, dialog: "Loaded \(node.displayName).")
    }
}

struct GetNodePortsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Node Ports"
    static let description = IntentDescription("List ports for a node in a graph.")

    @Parameter(title: "Node")
    var node: FabricNodeEntity

    func perform() async throws -> some IntentResult & ReturnsValue<[FabricPortEntity]> & ProvidesDialog {
        let ports = try await FabricDocumentAutomationService.shared.ports(for: self.node)
        return .result(value: ports, dialog: "Found \(ports.count) ports.")
    }
}

struct ConnectPortsIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect Ports"
    static let description = IntentDescription("Connect one outlet port to one inlet port.")

    @Parameter(title: "Source Port")
    var sourcePort: FabricPortEntity

    @Parameter(title: "Destination Port")
    var destinationPort: FabricPortEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await FabricDocumentAutomationService.shared.connectPorts(from: self.sourcePort, to: self.destinationPort)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct DisconnectPortsIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnect Ports"
    static let description = IntentDescription("Disconnect a specific port pair or all connections on a source port.")

    @Parameter(title: "Source Port")
    var sourcePort: FabricPortEntity

    @Parameter(title: "Destination Port")
    var destinationPort: FabricPortEntity?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let message = try await  FabricDocumentAutomationService.shared.disconnectPorts(from: self.sourcePort, to: self.destinationPort)
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

struct FabricEditorShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenGraphIntent(),
            phrases: [
                "Open a graph in \(.applicationName)",
                "Open a Fabric graph with \(.applicationName)",
            ],
            shortTitle: "Open Graph",
            systemImageName: "folder"
        )

        AppShortcut(
            intent: ListPublishedParametersIntent(),
            phrases: [
                "List published parameters in \(.applicationName)",
                "Get graph controls from \(.applicationName)",
            ],
            shortTitle: "Published Parameters",
            systemImageName: "slider.horizontal.3"
        )

        AppShortcut(
            intent: SetPublishedParametersIntent(),
            phrases: [
                "Set published parameters in \(.applicationName)",
                "Update graph controls with \(.applicationName)",
            ],
            shortTitle: "Set Parameters",
            systemImageName: "slider.horizontal.below.rectangle"
        )

        AppShortcut(
            intent: AddNodeToGraphIntent(),
            phrases: [
                "Add a Fabric node with \(.applicationName)",
            ],
            shortTitle: "Add Node",
            systemImageName: "plus.square.on.square"
        )
    }
}
