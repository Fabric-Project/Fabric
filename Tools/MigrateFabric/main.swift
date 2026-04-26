// =============================================================================
// MigrateFabric — TEMPORARY MIGRATION TOOL
// =============================================================================
//
// Interim utility for migrating saved .fabric graphs whose node declared port
// types have been changed in source without a runtime migration system in
// place.
//
// Specifically: rewrites port snapshots whose `isParameterPort` flag no longer
// matches the current declared port type, by encoding fresh declared ports
// from the current Fabric library and substituting them in. Saved port UUIDs
// are preserved so existing connections continue to resolve.
//
// SCOPE: covers commit 5d847c5 ("Use ParameterPort for all string node inputs
// where possible", Apr 2026) for the affected classes that retain their
// original class names. Classes renamed since (StringSeparatorNode,
// StringToTimecodeNode, StringComponentNode, DateFormatterNode) are not
// covered — they need combined class-name + port-type migration; add entries
// to `migrations` and `factories` if you hit them.
//
// REPLACE WITH a proper Fabric-wide migration system (versioned schema,
// per-node migration hooks) before this list grows.
//
// Usage:
//   swift run migrate-fabric <input.fabric> <output.fabric>
// =============================================================================

import Foundation
import Metal
import Fabric
import Satin

@main
struct MigrateFabric {

    /// Migration registry. Keys are encoded node class names (`String(describing:
    /// type(of: node))`), values are the registry-key port names whose declared
    /// type changed from `NodePort<T>` to `ParameterPort<T>` in commit 5d847c5.
    static let migrations: [String: [String]] = [
        "StringCaseNode":    ["inputPort"],
        "StringLengthNode":  ["inputPort"],
        "StringRangeNode":   ["inputPort"],
        "StringScannerNode": ["inputString"],
        "StringTrimNode":    ["inputPort"],
    ]

    /// Hint when uncovered renamed classes appear in a saved file.
    static let renamedHints: [String: String] = [
        "DateFormatterNode":    "renamed since 5d847c5 — not covered",
        "StringSeparatorNode":  "renamed since 5d847c5 — not covered",
        "StringToTimecodeNode": "renamed to Timecode — not covered",
        "StringComponentNode":  "removed since 5d847c5 — not covered",
    ]

    static func makeFactories(context: Context) -> [String: () -> Node] {
        [
            "StringCaseNode":    { StringCaseNode(context: context) },
            "StringLengthNode":  { StringLengthNode(context: context) },
            "StringRangeNode":   { StringRangeNode(context: context) },
            "StringScannerNode": { StringScannerNode(context: context) },
            "StringTrimNode":    { StringTrimNode(context: context) },
        ]
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            stderr("Usage: \(args[0]) <input.fabric> <output.fabric>\n")
            exit(64)
        }
        let input = URL(fileURLWithPath: args[1])
        let output = URL(fileURLWithPath: args[2])

        guard let device = MTLCreateSystemDefaultDevice() else {
            stderr("Error: no Metal device available\n")
            exit(1)
        }
        let context = Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
        let factories = makeFactories(context: context)
        let encoder = JSONEncoder()

        let data = try Data(contentsOf: input)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            stderr("Error: input is not a JSON object\n")
            exit(1)
        }
        guard var nodeMap = root["nodeMap"] as? [[String: Any]] else {
            stderr("Error: missing or invalid nodeMap\n")
            exit(1)
        }

        var migratedCount = 0
        var seenRenamed: Set<String> = []

        for nodeIdx in 0..<nodeMap.count {
            var nodeEntry = nodeMap[nodeIdx]
            guard let typeName = nodeEntry["type"] as? String else { continue }

            // Surface uncovered renamed classes as we encounter them.
            if let hint = renamedHints[typeName], !seenRenamed.contains(typeName) {
                stderr("note: \(typeName) present — \(hint)\n")
                seenRenamed.insert(typeName)
            }

            guard let portsToMigrate = migrations[typeName],
                  let factory = factories[typeName] else { continue }
            guard var nodeValue = nodeEntry["value"] as? [String: Any],
                  var ports = nodeValue["ports"] as? [[String: Any]] else { continue }

            // Encode a fresh declared instance once and index its ports by registry name.
            let freshNode = factory()
            let freshNodeData = try encoder.encode(freshNode)
            guard let freshNodeJSON = try JSONSerialization.jsonObject(with: freshNodeData) as? [String: Any],
                  let freshPorts = freshNodeJSON["ports"] as? [[String: Any]] else { continue }
            var freshByName: [String: [String: Any]] = [:]
            for snap in freshPorts {
                if let n = snap["name"] as? String { freshByName[n] = snap }
            }

            for portIdx in 0..<ports.count {
                var savedSnapshot = ports[portIdx]
                guard let portName = savedSnapshot["name"] as? String,
                      portsToMigrate.contains(portName) else { continue }
                guard let savedPayload = savedSnapshot["payload"] as? [String: Any] else { continue }

                if let isParam = savedPayload["isParameterPort"] as? Bool, isParam {
                    continue // already migrated
                }

                guard let savedBase = savedPayload["base"] as? [String: Any],
                      let savedID = savedBase["id"] as? String else {
                    stderr("warn: \(typeName).\(portName) saved snapshot missing base/id — skipping\n")
                    continue
                }

                guard let freshSnap = freshByName[portName],
                      var freshPayload = freshSnap["payload"] as? [String: Any],
                      var freshBase = freshPayload["base"] as? [String: Any] else {
                    stderr("warn: \(typeName) no longer declares port '\(portName)' — skipping\n")
                    continue
                }

                // Preserve saved identity + user state.
                freshBase["id"] = savedID
                if let v = savedBase["connections"]   { freshBase["connections"] = v }
                if let v = savedBase["published"]     { freshBase["published"] = v }
                if let v = savedBase["publishedName"] { freshBase["publishedName"] = v }

                freshPayload["base"] = freshBase
                savedSnapshot["payload"] = freshPayload
                ports[portIdx] = savedSnapshot
                migratedCount += 1
                print("Migrated: \(typeName).\(portName) (NodePort → ParameterPort, id \(savedID))")
            }

            nodeValue["ports"] = ports
            nodeEntry["value"] = nodeValue
            nodeMap[nodeIdx] = nodeEntry
        }

        root["nodeMap"] = nodeMap
        let outData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try outData.write(to: output)

        print("---")
        print("Migrated \(migratedCount) port(s)")
        print("Wrote: \(output.path)")
    }

    static func stderr(_ s: String) {
        FileHandle.standardError.write(Data(s.utf8))
    }
}
