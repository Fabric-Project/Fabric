import Foundation
@testable import Fabric
import Satin

/// Builds documents in the form saved before ports were addressed (version
/// beta): port envelopes with ids, wires by port id, publishing on the port.
/// The writer for that form is gone, so tests of the reader write it by hand.
struct LegacyDocumentFixture
{
    struct SavedPort
    {
        var key: String
        var type: String
        var kind: String = "Inlet"
        var id = UUID()
        var name: String
        /// A parameter port's parameter type and value, as Satin encoded them.
        var parameter: (type: String, value: Any)?
        var published = false
        var publishedName: String?
        /// Saved at the node's top level under `key`, as nodes with stored
        /// port properties wrote them, rather than in its ports list.
        var savedOutsideList = false

        var envelope: [String: Any]
        {
            var base: [String: Any] = ["id": id.uuidString, "name": name, "kind": kind, "published": published]
            if let publishedName { base["publishedName"] = publishedName }
            if let parameter
            {
                base["parameter"] = ["type": parameter.type,
                                     "base": ["label": name, "value": parameter.value, "id": id.uuidString, "controlType": "inputfield"]]
            }
            return base
        }
    }

    struct SavedNode
    {
        var type: String
        var id = UUID()
        var ports: [SavedPort]
        var extra: [String: Any] = [:]
        /// For a subgraph node: its inner graph, and the proxies it saved.
        var subGraph: LegacyDocumentFixture?
        var proxies: [(id: UUID, innerPortID: UUID, type: String, kind: String, published: Bool, publishedName: String?)] = []

        func value() -> [String: Any]
        {
            var value: [String: Any] = ["id": id.uuidString, "nodeOffset": [0, 0]]
            var list: [[String: Any]] = []
            for port in ports
            {
                if port.savedOutsideList
                {
                    value[port.key] = port.envelope
                }
                else
                {
                    list.append(["name": port.key,
                                 "payload": ["type": port.type, "isParameterPort": port.parameter != nil, "isProxyPort": false, "base": port.envelope]])
                }
            }
            value["ports"] = list
            if let subGraph
            {
                value["subGraph"] = subGraph.document()
                value["proxyPorts"] = proxies.map { proxy -> [String: Any] in
                    var base: [String: Any] = ["id": proxy.id.uuidString, "innerPortID": proxy.innerPortID.uuidString,
                                               "kind": proxy.kind, "name": "Proxy", "published": proxy.published]
                    if let name = proxy.publishedName { base["publishedName"] = name }
                    return ["type": proxy.type, "isParameterPort": false, "isProxyPort": true, "base": base]
                }
            }
            value.merge(extra) { _, new in new }
            return value
        }
    }

    var id = UUID()
    var nodes: [SavedNode]
    /// Wires by outlet then inlet port id.
    var connections: [(UUID, UUID)] = []
    /// Write the wires as the legacy map, each under both endpoints.
    var asConnectionMap = false

    func document() -> [String: Any]
    {
        var document: [String: Any] = ["id": id.uuidString, "version": ["beta": [String: Any]()], "notes": [],
                                       "nodeMap": nodes.map { ["type": $0.type, "value": $0.value()] }]
        if asConnectionMap
        {
            var map: [String: [String]] = [:]
            for (outlet, inlet) in connections
            {
                map[outlet.uuidString, default: []].append(inlet.uuidString)
                map[inlet.uuidString, default: []].append(outlet.uuidString)
            }
            document["portConnectionMap"] = map
        }
        else
        {
            document["connections"] = connections.map { ["id": UUID().uuidString, "outletPortID": $0.0.uuidString,
                                                          "inletPortID": $0.1.uuidString, "active": true] }
        }
        return document
    }

    func decode(context: Context) throws -> Graph
    {
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return try decoder.decode(Graph.self, from: JSONSerialization.data(withJSONObject: document()))
    }

    /// A Number Binary Operator as beta saved it.
    static func numberBinaryOperator(a: Float = 0, b: Float = 0) -> (node: SavedNode, inputA: SavedPort, inputB: SavedPort, output: SavedPort)
    {
        let inputA = SavedPort(key: "inputNumber1", type: "Float", name: "Number A", parameter: ("float", a))
        let inputB = SavedPort(key: "inputNumber2", type: "Float", name: "Number B", parameter: ("float", b))
        let operation = SavedPort(key: "inputParam", type: "String", name: "Operator", parameter: ("string", "Add"))
        let output = SavedPort(key: "outputNumber", type: "Float", kind: "Outlet", name: "Number")
        return (SavedNode(type: "NumberBinaryOperator", ports: [inputA, inputB, operation, output]), inputA, inputB, output)
    }
}
