// =============================================================================
// MigrateFabric — TEMPORARY MIGRATION TOOL
// =============================================================================
//
// Interim utility for migrating saved .fabric graphs whose schema has drifted
// from the current Fabric library. Two migration kinds are supported:
//
//   1. Port-type swap (commit 5d847c5):
//      Same class, a declared port's type changed from `NodePort<T>` to
//      `ParameterPort<T>`. Saved port snapshots are re-wrapped using a fresh
//      declared instance while preserving saved UUIDs and connections.
//
//   2. Class rename (deletion of NumberNode / StringNode / TrueNode /
//      FalseNode / IdentityTransformNode in favour of `PassThroughNode<T>`):
//      The saved node's `type` string is rewritten and its port snapshots
//      renamed (e.g. `inputNumber` → `input`). Saved port UUIDs, connections,
//      published flags and parameter values are preserved. Fresh ports the
//      replacement class declares but the old class lacked are added from a
//      template instance — `True/FalseNode` migrate to a `PassThroughNode<Bool>`
//      whose newly-added `input` parameter is pre-set to `true`/`false`, and
//      `IdentityTransformNode` migrates to a `PassThroughNode<simd_float4x4>`
//      whose new `input` is pre-set to the identity matrix.
//
// Subgraphs (including `StateSubgraphNode`) are recursed: nested node maps
// inside a node's encoded `value.subGraph` are migrated before the container.
//
// Classes renamed since 5d847c5 that aren't in the table (e.g. `DateFormatterNode`)
// are still flagged as warnings — add an entry to `classRenames` if you hit them.
//
// REPLACE WITH a proper Fabric-wide migration system (versioned schema,
// per-node migration hooks) before this list grows further.
//
// Usage:
//   swift run migrate-fabric <input.fabric> <output.fabric>
// =============================================================================

import Foundation
import Metal
import simd
import Fabric
import Satin

@main
struct MigrateFabric {

    // MARK: - Port-type-swap migrations (5d847c5)

    /// Same class, port's declared type changed from NodePort<T> to ParameterPort<T>.
    /// Keys: encoded class names; values: the registry-key port names that swapped.
    static let portTypeSwaps: [String: [String]] = [
        "StringCaseNode":    ["inputPort"],
        "StringLengthNode":  ["inputPort"],
        "StringRangeNode":   ["inputPort"],
        "StringScannerNode": ["inputString"],
        "StringTrimNode":    ["inputPort"],
    ]

    static func makePortSwapFactories(context: Context) -> [String: () -> Node] {
        [
            "StringCaseNode":    { StringCaseNode(context: context) },
            "StringLengthNode":  { StringLengthNode(context: context) },
            "StringRangeNode":   { StringRangeNode(context: context) },
            "StringScannerNode": { StringScannerNode(context: context) },
            "StringTrimNode":    { StringTrimNode(context: context) },
        ]
    }

    // MARK: - Class-rename migrations

    /// Specification for renaming a deleted class onto its replacement.
    struct ClassRename {
        /// `String(describing:)` of the replacement class — written to the saved
        /// node's `type` field.
        let newName: String
        /// Saved port name → replacement port name. Saved port snapshots whose
        /// names aren't in the map are dropped.
        let portRenames: [String: String]
        /// Builds a fresh instance whose encoded port snapshots fill in any
        /// ports the new class declares but the old class lacked. Use the
        /// closure to pre-set defaults (e.g. `input.value = true` for TrueNode).
        let makeTemplate: (Context) -> Node
    }

    static let classRenames: [String: ClassRename] = [
        "NumberNode": ClassRename(
            newName: String(describing: PassThroughNode<Float>.self),
            portRenames: ["inputNumber": "input", "outputNumber": "output"],
            makeTemplate: { ctx in PassThroughNode<Float>(context: ctx) }
        ),
        "StringNode": ClassRename(
            newName: String(describing: PassThroughNode<String>.self),
            portRenames: ["inputPort": "input", "outputPort": "output"],
            makeTemplate: { ctx in PassThroughNode<String>(context: ctx) }
        ),
        "TrueNode": ClassRename(
            newName: String(describing: PassThroughNode<Bool>.self),
            portRenames: ["outputBoolean": "output"],
            makeTemplate: { ctx in
                let n = PassThroughNode<Bool>(context: ctx)
                n.input.value = true
                return n
            }
        ),
        "FalseNode": ClassRename(
            newName: String(describing: PassThroughNode<Bool>.self),
            portRenames: ["outputBoolean": "output"],
            makeTemplate: { ctx in
                let n = PassThroughNode<Bool>(context: ctx)
                n.input.value = false
                return n
            }
        ),
        "IdentityTransformNode": ClassRename(
            newName: String(describing: PassThroughNode<simd_float4x4>.self),
            portRenames: ["outputTransform": "output"],
            makeTemplate: { ctx in
                let n = PassThroughNode<simd_float4x4>(context: ctx)
                n.input.value = matrix_identity_float4x4
                return n
            }
        ),
    ]

    /// Hint when uncovered renamed classes appear in a saved file.
    static let renamedHints: [String: String] = [
        "DateFormatterNode":    "renamed since 5d847c5 — not covered",
        "StringSeparatorNode":  "renamed since 5d847c5 — not covered",
        "StringToTimecodeNode": "renamed to Timecode — not covered",
        "StringComponentNode":  "removed since 5d847c5 — not covered",
    ]

    // MARK: - Counters threaded through recursive walk

    final class Counters {
        var portsSwapped = 0
        var classesRenamed = 0
        var seenRenamed: Set<String> = []
    }

    // MARK: - Entry

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
        let portSwapFactories = makePortSwapFactories(context: context)
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

        let counters = Counters()
        try migrate(nodeMap: &nodeMap,
                    encoder: encoder,
                    context: context,
                    portSwapFactories: portSwapFactories,
                    counters: counters)

        root["nodeMap"] = nodeMap
        let outData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try outData.write(to: output)

        print("---")
        print("Migrated \(counters.portsSwapped) port(s); renamed \(counters.classesRenamed) class instance(s).")
        print("Wrote: \(output.path)")
    }

    // MARK: - Recursive nodeMap walker

    /// Migrates a `nodeMap` array in place, recursing into any node's
    /// encoded `value.subGraph.nodeMap` first so a class rename inside a
    /// SubgraphNode lands before its parent ProxyPorts try to rebind.
    static func migrate(
        nodeMap: inout [[String: Any]],
        encoder: JSONEncoder,
        context: Context,
        portSwapFactories: [String: () -> Node],
        counters: Counters
    ) throws {
        for nodeIdx in 0..<nodeMap.count {
            var nodeEntry = nodeMap[nodeIdx]
            guard let typeName = nodeEntry["type"] as? String,
                  var nodeValue = nodeEntry["value"] as? [String: Any] else {
                continue
            }

            // Recurse into nested subgraph first so nested class renames
            // settle before we touch this node's surface.
            if var subGraph = nodeValue["subGraph"] as? [String: Any],
               var nestedNodeMap = subGraph["nodeMap"] as? [[String: Any]] {
                try migrate(nodeMap: &nestedNodeMap,
                            encoder: encoder,
                            context: context,
                            portSwapFactories: portSwapFactories,
                            counters: counters)
                subGraph["nodeMap"] = nestedNodeMap
                nodeValue["subGraph"] = subGraph
            }

            // Surface uncovered renamed classes.
            if let hint = renamedHints[typeName], !counters.seenRenamed.contains(typeName) {
                stderr("note: \(typeName) present — \(hint)\n")
                counters.seenRenamed.insert(typeName)
            }

            // Class rename: rewrite type + port names, fill in new ports.
            if let rename = classRenames[typeName] {
                try applyClassRename(rename,
                                     oldTypeName: typeName,
                                     nodeValue: &nodeValue,
                                     encoder: encoder,
                                     context: context,
                                     counters: counters)
                nodeEntry["type"] = rename.newName
            }
            // Port-type swap: keep class, rewrap declared port snapshots.
            else if let portsToSwap = portTypeSwaps[typeName],
                    let factory = portSwapFactories[typeName] {
                try applyPortTypeSwap(typeName: typeName,
                                      portsToSwap: portsToSwap,
                                      factory: factory,
                                      nodeValue: &nodeValue,
                                      encoder: encoder,
                                      counters: counters)
            }

            nodeEntry["value"] = nodeValue
            nodeMap[nodeIdx] = nodeEntry
        }
    }

    // MARK: - Class rename

    static func applyClassRename(
        _ rename: ClassRename,
        oldTypeName: String,
        nodeValue: inout [String: Any],
        encoder: JSONEncoder,
        context: Context,
        counters: Counters
    ) throws {
        let savedPorts = (nodeValue["ports"] as? [[String: Any]]) ?? []

        // Encode a fresh template instance to pull port snapshots for any
        // ports the new class adds (e.g. `input` when migrating from True/False).
        let template = rename.makeTemplate(context)
        let templateData = try encoder.encode(template)
        guard let templateJSON = try JSONSerialization.jsonObject(with: templateData) as? [String: Any],
              let templatePorts = templateJSON["ports"] as? [[String: Any]] else {
            stderr("warn: \(oldTypeName) → \(rename.newName) template encoding has no ports — skipping\n")
            return
        }
        var templateByName: [String: [String: Any]] = [:]
        for snap in templatePorts {
            if let n = snap["name"] as? String { templateByName[n] = snap }
        }

        var migratedPorts: [[String: Any]] = []
        var renamedTargets: Set<String> = []

        for var snap in savedPorts {
            guard let oldName = snap["name"] as? String else {
                migratedPorts.append(snap)
                continue
            }
            if let newName = rename.portRenames[oldName] {
                snap["name"] = newName
                migratedPorts.append(snap)
                renamedTargets.insert(newName)
            }
            // Saved ports not in the rename map are dropped — the new class
            // doesn't declare them and keeping them would just leave dead snapshots.
        }

        // Append fresh ports the new class declares that we haven't filled
        // from saved data (e.g. the `input` for a TrueNode/FalseNode migration).
        for (newName, snap) in templateByName where !renamedTargets.contains(newName) {
            migratedPorts.append(snap)
        }

        nodeValue["ports"] = migratedPorts
        counters.classesRenamed += 1
        print("Renamed: \(oldTypeName) → \(rename.newName)")
    }

    // MARK: - Port-type swap (existing 5d847c5 path)

    static func applyPortTypeSwap(
        typeName: String,
        portsToSwap: [String],
        factory: () -> Node,
        nodeValue: inout [String: Any],
        encoder: JSONEncoder,
        counters: Counters
    ) throws {
        guard var ports = nodeValue["ports"] as? [[String: Any]] else { return }

        let freshNode = factory()
        let freshNodeData = try encoder.encode(freshNode)
        guard let freshNodeJSON = try JSONSerialization.jsonObject(with: freshNodeData) as? [String: Any],
              let freshPorts = freshNodeJSON["ports"] as? [[String: Any]] else { return }
        var freshByName: [String: [String: Any]] = [:]
        for snap in freshPorts {
            if let n = snap["name"] as? String { freshByName[n] = snap }
        }

        for portIdx in 0..<ports.count {
            var savedSnapshot = ports[portIdx]
            guard let portName = savedSnapshot["name"] as? String,
                  portsToSwap.contains(portName) else { continue }
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
            counters.portsSwapped += 1
            print("Swapped: \(typeName).\(portName) (NodePort → ParameterPort, id \(savedID))")
        }

        nodeValue["ports"] = ports
    }

    // MARK: -

    static func stderr(_ s: String) {
        FileHandle.standardError.write(Data(s.utf8))
    }
}
