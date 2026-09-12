//
//  FabricIntentEntities.swift
//  Fabric Editor
//
//  Created by Codex on 4/7/26.
//

import AppIntents
import Foundation

enum FabricIntentIdentifierCodec {
    static func encode(_ payload: [String: String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return data?.base64EncodedString() ?? ""
    }

    static func decode(_ identifier: String) -> [String: String] {
        guard
            let data = Data(base64Encoded: identifier),
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: String]
        else {
            return [:]
        }

        return payload
    }
}

struct FabricGraphEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Graph"
    static let defaultQuery = FabricGraphEntityQuery()

    let id: String
    let graphURL: String
    let displayName: String
    let graphIdentifier: String
    let nodeCount: Int
    let publishedParameterCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: self.displayName),
            subtitle: LocalizedStringResource(stringLiteral: "\(self.nodeCount) nodes • \(self.publishedParameterCount) published")
        )
    }

    init(
        graphURL: String,
        displayName: String,
        graphIdentifier: String,
        nodeCount: Int,
        publishedParameterCount: Int
    ) {
        self.graphURL = graphURL
        self.displayName = displayName
        self.graphIdentifier = graphIdentifier
        self.nodeCount = nodeCount
        self.publishedParameterCount = publishedParameterCount
        self.id = FabricIntentIdentifierCodec.encode([
            "kind": "graph",
            "graphURL": graphURL,
            "displayName": displayName,
            "graphIdentifier": graphIdentifier,
            "nodeCount": String(nodeCount),
            "publishedParameterCount": String(publishedParameterCount),
        ])
    }

    fileprivate init?(id: String) {
        let payload = FabricIntentIdentifierCodec.decode(id)
        guard
            payload["kind"] == "graph",
            let graphURL = payload["graphURL"],
            let displayName = payload["displayName"],
            let graphIdentifier = payload["graphIdentifier"],
            let nodeCountValue = payload["nodeCount"],
            let publishedParameterCountValue = payload["publishedParameterCount"],
            let nodeCount = Int(nodeCountValue),
            let publishedParameterCount = Int(publishedParameterCountValue)
        else {
            return nil
        }

        self.id = id
        self.graphURL = graphURL
        self.displayName = displayName
        self.graphIdentifier = graphIdentifier
        self.nodeCount = nodeCount
        self.publishedParameterCount = publishedParameterCount
    }
}

struct FabricNodeEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Node"
    static let defaultQuery = FabricNodeEntityQuery()

    let id: String
    let graphURL: String
    let nodeIdentifier: String
    let displayName: String
    let nodeClassName: String
    let nodeTypeDescription: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: self.displayName),
            subtitle: LocalizedStringResource(stringLiteral: "\(self.nodeTypeDescription) • \(self.nodeClassName)")
        )
    }

    init(
        graphURL: String,
        nodeIdentifier: String,
        displayName: String,
        nodeClassName: String,
        nodeTypeDescription: String
    ) {
        self.graphURL = graphURL
        self.nodeIdentifier = nodeIdentifier
        self.displayName = displayName
        self.nodeClassName = nodeClassName
        self.nodeTypeDescription = nodeTypeDescription
        self.id = FabricIntentIdentifierCodec.encode([
            "kind": "node",
            "graphURL": graphURL,
            "nodeIdentifier": nodeIdentifier,
            "displayName": displayName,
            "nodeClassName": nodeClassName,
            "nodeTypeDescription": nodeTypeDescription,
        ])
    }

    fileprivate init?(id: String) {
        let payload = FabricIntentIdentifierCodec.decode(id)
        guard
            payload["kind"] == "node",
            let graphURL = payload["graphURL"],
            let nodeIdentifier = payload["nodeIdentifier"],
            let displayName = payload["displayName"],
            let nodeClassName = payload["nodeClassName"],
            let nodeTypeDescription = payload["nodeTypeDescription"]
        else {
            return nil
        }

        self.id = id
        self.graphURL = graphURL
        self.nodeIdentifier = nodeIdentifier
        self.displayName = displayName
        self.nodeClassName = nodeClassName
        self.nodeTypeDescription = nodeTypeDescription
    }
}

struct FabricPortEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Port"
    static let defaultQuery = FabricPortEntityQuery()

    let id: String
    let graphURL: String
    let nodeIdentifier: String
    let portIdentifier: String
    let portName: String
    let portDisplayName: String
    let kind: String
    let portType: String
    let isPublished: Bool
    let connectionCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: self.portDisplayName),
            subtitle: LocalizedStringResource(stringLiteral: "\(self.kind) • \(self.portType) • \(self.connectionCount) connections")
        )
    }

    init(
        graphURL: String,
        nodeIdentifier: String,
        portIdentifier: String,
        portName: String,
        portDisplayName: String,
        kind: String,
        portType: String,
        isPublished: Bool,
        connectionCount: Int
    ) {
        self.graphURL = graphURL
        self.nodeIdentifier = nodeIdentifier
        self.portIdentifier = portIdentifier
        self.portName = portName
        self.portDisplayName = portDisplayName
        self.kind = kind
        self.portType = portType
        self.isPublished = isPublished
        self.connectionCount = connectionCount
        self.id = FabricIntentIdentifierCodec.encode([
            "kind": "port",
            "graphURL": graphURL,
            "nodeIdentifier": nodeIdentifier,
            "portIdentifier": portIdentifier,
            "portName": portName,
            "portDisplayName": portDisplayName,
            "portKind": kind,
            "portType": portType,
            "isPublished": String(isPublished),
            "connectionCount": String(connectionCount),
        ])
    }

    fileprivate init?(id: String) {
        let payload = FabricIntentIdentifierCodec.decode(id)
        guard
            payload["kind"] == "port",
            let graphURL = payload["graphURL"],
            let nodeIdentifier = payload["nodeIdentifier"],
            let portIdentifier = payload["portIdentifier"],
            let portName = payload["portName"],
            let portDisplayName = payload["portDisplayName"],
            let kind = payload["portKind"],
            let portType = payload["portType"],
            let isPublishedValue = payload["isPublished"],
            let connectionCountValue = payload["connectionCount"],
            let isPublished = Bool(isPublishedValue),
            let connectionCount = Int(connectionCountValue)
        else {
            return nil
        }

        self.id = id
        self.graphURL = graphURL
        self.nodeIdentifier = nodeIdentifier
        self.portIdentifier = portIdentifier
        self.portName = portName
        self.portDisplayName = portDisplayName
        self.kind = kind
        self.portType = portType
        self.isPublished = isPublished
        self.connectionCount = connectionCount
    }
}

struct FabricPublishedParameterEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Published Parameter"
    static let defaultQuery = FabricPublishedParameterEntityQuery()

    let id: String
    let graphURL: String
    let parameterIdentifier: String
    let publishedPortIdentifier: String
    let label: String
    let valueSummary: String
    let controlType: String
    let parameterType: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: self.label),
            subtitle: LocalizedStringResource(stringLiteral: "\(self.parameterType) • \(self.valueSummary)")
        )
    }

    init(
        graphURL: String,
        parameterIdentifier: String,
        publishedPortIdentifier: String,
        label: String,
        valueSummary: String,
        controlType: String,
        parameterType: String
    ) {
        self.graphURL = graphURL
        self.parameterIdentifier = parameterIdentifier
        self.publishedPortIdentifier = publishedPortIdentifier
        self.label = label
        self.valueSummary = valueSummary
        self.controlType = controlType
        self.parameterType = parameterType
        self.id = FabricIntentIdentifierCodec.encode([
            "kind": "publishedParameter",
            "graphURL": graphURL,
            "parameterIdentifier": parameterIdentifier,
            "publishedPortIdentifier": publishedPortIdentifier,
            "label": label,
            "valueSummary": valueSummary,
            "controlType": controlType,
            "parameterType": parameterType,
        ])
    }

    fileprivate init?(id: String) {
        let payload = FabricIntentIdentifierCodec.decode(id)
        guard
            payload["kind"] == "publishedParameter",
            let graphURL = payload["graphURL"],
            let parameterIdentifier = payload["parameterIdentifier"],
            let publishedPortIdentifier = payload["publishedPortIdentifier"],
            let label = payload["label"],
            let valueSummary = payload["valueSummary"],
            let controlType = payload["controlType"],
            let parameterType = payload["parameterType"]
        else {
            return nil
        }

        self.id = id
        self.graphURL = graphURL
        self.parameterIdentifier = parameterIdentifier
        self.publishedPortIdentifier = publishedPortIdentifier
        self.label = label
        self.valueSummary = valueSummary
        self.controlType = controlType
        self.parameterType = parameterType
    }
}

struct FabricRegistryNodeEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fabric Registry Node"
    static let defaultQuery = FabricRegistryNodeEntityQuery()

    let id: String
    let nodeName: String
    let nodeClassName: String
    let nodeTypeDescription: String
    let nodeDescription: String
    let sourcePath: String?

    var displayRepresentation: DisplayRepresentation {
        let subtitleText = self.sourcePath.map { "\(self.nodeTypeDescription) • \($0)" } ?? self.nodeTypeDescription
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: self.nodeName),
            subtitle: LocalizedStringResource(stringLiteral: subtitleText)
        )
    }

    init(
        nodeName: String,
        nodeClassName: String,
        nodeTypeDescription: String,
        nodeDescription: String,
        sourcePath: String?
    ) {
        self.nodeName = nodeName
        self.nodeClassName = nodeClassName
        self.nodeTypeDescription = nodeTypeDescription
        self.nodeDescription = nodeDescription
        self.sourcePath = sourcePath
        self.id = FabricIntentIdentifierCodec.encode([
            "kind": "registryNode",
            "nodeName": nodeName,
            "nodeClassName": nodeClassName,
            "nodeTypeDescription": nodeTypeDescription,
            "nodeDescription": nodeDescription,
            "sourcePath": sourcePath ?? "",
        ])
    }

    fileprivate init?(id: String) {
        let payload = FabricIntentIdentifierCodec.decode(id)
        guard
            payload["kind"] == "registryNode",
            let nodeName = payload["nodeName"],
            let nodeClassName = payload["nodeClassName"],
            let nodeTypeDescription = payload["nodeTypeDescription"],
            let nodeDescription = payload["nodeDescription"]
        else {
            return nil
        }

        self.id = id
        self.nodeName = nodeName
        self.nodeClassName = nodeClassName
        self.nodeTypeDescription = nodeTypeDescription
        self.nodeDescription = nodeDescription
        let sourcePath = payload["sourcePath"] ?? ""
        self.sourcePath = sourcePath.isEmpty ? nil : sourcePath
    }
}

struct FabricGraphEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FabricGraphEntity] {
        identifiers.compactMap(FabricGraphEntity.init(id:))
    }

    func suggestedEntities() async throws -> [FabricGraphEntity] {
        []
    }
}

struct FabricNodeEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FabricNodeEntity] {
        identifiers.compactMap(FabricNodeEntity.init(id:))
    }

    func suggestedEntities() async throws -> [FabricNodeEntity] {
        []
    }
}

struct FabricPortEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FabricPortEntity] {
        identifiers.compactMap(FabricPortEntity.init(id:))
    }

    func suggestedEntities() async throws -> [FabricPortEntity] {
        []
    }
}

struct FabricPublishedParameterEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FabricPublishedParameterEntity] {
        identifiers.compactMap(FabricPublishedParameterEntity.init(id:))
    }

    func suggestedEntities() async throws -> [FabricPublishedParameterEntity] {
        []
    }
}

struct FabricRegistryNodeEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FabricRegistryNodeEntity] {
        identifiers.compactMap(FabricRegistryNodeEntity.init(id:))
    }

    func suggestedEntities() async throws -> [FabricRegistryNodeEntity] {
        []
    }
}
