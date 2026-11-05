//
//  GraphFormatMigration.swift
//  Fabric
//

import Foundation

/// Reads a graph saved before ports were addressed (versions alpha1 and beta)
/// into the current form, as JSON, once at open. The old port envelopes are
/// understood here and nowhere else: each is reduced to the address it stands
/// at, its published flag and name, and a parameter inlet's value. Forward
/// only; the writer never emits the old form.
///
/// The envelopes give no node its interface. A script, shader or expression
/// that compiles on open declares its ports as it would in any document; one
/// that does not has no last compiled source in an old document, so it opens
/// without those ports and their wires drop, as a new document saved with a
/// source that does not compile and never did would.
enum GraphFormatMigration
{
    /// Ports a node type saved under a key it no longer declares them by,
    /// whether the old document kept the port in its registry or under a
    /// coding key of its own.
    private static let renamedKeys: [String: [String: String]] = [
        "ImageDimensions": ["inputTexturePort": "inputImage", "outputResolutionPort": "legacyOutputResolution"],
        "ForegroundMaskNode": ["inputTexturePort": "inputImage"],
        "PersonSegmentationMaskNode": ["inputTexturePort": "inputImage"],
        "LocalVLMNode": ["inputTexturePort": "inputImage"],
        "UnitsoPixelsNode": ["outputCursorPositionPort": "outputPixelPositionPort"],
        "PixelsToUnitsNode": ["inputCursorPositionPort": "inputPixelPositionPort"],
    ]

    private struct SavedPort
    {
        let node: String
        let key: Any
        let isOutlet: Bool
    }

    private struct Level
    {
        var graph: [String: Any]
        var ports: [String: SavedPort]
        /// Ids of the ports this graph published, in document order.
        var publishedPortIDs: [String]
    }

    static func migrate(_ graph: [String: Any], to version: Any) -> [String: Any]
    {
        migrateLevel(graph, version: version).graph
    }

    private static func migrateLevel(_ source: [String: Any], version: Any) -> Level
    {
        var graph = source
        var ports: [String: SavedPort] = [:]
        var publishedPortIDs: [String] = []
        var published: [[String: Any]] = []

        func record(_ base: [String: Any], node: String, key: Any)
        {
            guard let id = base["id"] as? String else { return }
            ports[id] = SavedPort(node: node, key: key, isOutlet: base["kind"] as? String == "Outlet")
            if base["published"] as? Bool == true
            {
                publishedPortIDs.append(id)
                var entry: [String: Any] = ["port": [node, key]]
                if let name = base["publishedName"] as? String { entry["name"] = name }
                published.append(entry)
            }
        }

        var nodeMap = graph["nodeMap"] as? [[String: Any]] ?? []
        for index in nodeMap.indices
        {
            guard var value = nodeMap[index]["value"] as? [String: Any],
                  let nodeID = value["id"] as? String
            else { continue }
            let type = Self.unqualifiedType(nodeMap[index]["type"] as? String ?? "")
            var states: [String: Any] = [:]

            // A subgraph's inner graph first: its proxies are addressed by the
            // inner ports they stand for.
            if let subGraph = value["subGraph"] as? [String: Any]
            {
                let inner = migrateLevel(subGraph, version: version)
                value["subGraph"] = inner.graph

                for envelope in value["proxyPorts"] as? [[String: Any]] ?? []
                {
                    guard let base = envelope["base"] as? [String: Any],
                          let innerID = base["innerPortID"] as? String,
                          let innerPort = inner.ports[innerID]
                    else { continue }
                    record(base, node: nodeID, key: [innerPort.node, innerPort.key])
                }

                // A document with no saved proxies still wired to them by the
                // inner port's id, which is the id a proxy took.
                for innerID in inner.publishedPortIDs where ports[innerID] == nil
                {
                    guard let innerPort = inner.ports[innerID] else { continue }
                    ports[innerID] = SavedPort(node: nodeID, key: [innerPort.node, innerPort.key], isOutlet: innerPort.isOutlet)
                }
                value["proxyPorts"] = nil
            }

            func take(_ payload: [String: Any], base: [String: Any], key: String)
            {
                record(base, node: nodeID, key: key)
                let isParameterPort = payload["isParameterPort"] as? Bool ?? (base["parameter"] != nil)
                if isParameterPort, let state = Self.stateValue(portType: payload["type"] as? String, parameter: base["parameter"])
                {
                    states[key] = state
                }
            }

            for snapshot in value["ports"] as? [[String: Any]] ?? []
            {
                guard let key = snapshot["name"] as? String,
                      let payload = snapshot["payload"] as? [String: Any],
                      let base = payload["base"] as? [String: Any]
                else { continue }
                take(payload, base: base, key: Self.renamedKeys[type]?[key] ?? key)
            }

            // Nodes that kept ports in stored properties saved each under a
            // coding key of its own; the key is the port's address now.
            for (codingKey, saved) in value
            {
                guard let base = saved as? [String: Any],
                      base["kind"] is String, base["id"] is String
                else { continue }
                let key = Self.renamedKeys[type]?[codingKey] ?? codingKey
                take(["isParameterPort": base["parameter"] != nil], base: base, key: key)
                value[codingKey] = nil
                if type == "ImageDimensions", key == "legacyOutputResolution" { value["legacyOutputResolution"] = true }
            }

            value["ports"] = states
            nodeMap[index]["value"] = value
        }
        graph["nodeMap"] = nodeMap

        var connections: [[String: Any]] = []
        func address(_ id: String) -> [Any]
        {
            guard let port = ports[id] else { return [Self.unknownNode, "unresolved port \(id)"] }
            return [port.node, port.key]
        }

        if let saved = graph["connections"] as? [[String: Any]]
        {
            for connection in saved
            {
                guard let outlet = connection["outletPortID"] as? String,
                      let inlet = connection["inletPortID"] as? String
                else { continue }
                connections.append(["from": address(outlet), "to": address(inlet),
                                    "active": connection["active"] as? Bool ?? true])
            }
        }
        else if let map = graph["portConnectionMap"] as? [String: [String]]
        {
            // The legacy map holds each wire under both endpoints; take it once,
            // from its outlet, or from whichever end resolves.
            var seen = Set<[String]>()
            for (portID, connected) in map
            {
                for otherID in connected
                {
                    let (outlet, inlet) = ports[portID]?.isOutlet ?? !(ports[otherID]?.isOutlet ?? false)
                        ? (portID, otherID) : (otherID, portID)
                    guard seen.insert([outlet, inlet]).inserted else { continue }
                    connections.append(["from": address(outlet), "to": address(inlet), "active": true])
                }
            }
        }

        graph["connections"] = connections
        graph["portConnectionMap"] = nil
        graph["published"] = published
        graph["version"] = version
        return Level(graph: graph, ports: ports, publishedPortIDs: publishedPortIDs)
    }

    /// A connection endpoint the old document named by an id no port held.
    static let unknownNode = "00000000-0000-0000-0000-000000000000"

    private static func unqualifiedType(_ serializedType: String) -> String
    {
        serializedType.split(separator: "/").last.map(String.init) ?? serializedType
    }

    /// A parameter inlet's saved value, as PortValue's document form.
    private static func stateValue(portType: String?, parameter: Any?) -> Any?
    {
        guard let parameter = parameter as? [String: Any],
              parameter["type"] as? String != "generic",
              let base = parameter["base"] as? [String: Any],
              let value = base["value"],
              let portType
        else { return nil }

        switch portType
        {
        case "Bool": return ["Bool": value]
        case "Int": return ["Int": value]
        case "Float": return ["Float": value]
        case "String": return ["String": value]
        case "Vector 2": return ["Vector2": value]
        case "Vector 3": return ["Vector3": value]
        case "Vector 4", "Color": return ["Vector4": value]
        case "Quaternion": return ["Quaternion": value]
        case "Transform": return ["Transform": value]
        default: return nil
        }
    }
}
