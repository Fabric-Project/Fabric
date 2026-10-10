//
//  CloneSet.swift
//  Fabric
//
//  Created by Claude on 10/9/26.
//

import Foundation
internal import AnyCodable

/// A clone set: one stored graph, held as data, plus the set's name. Owned by
/// the document's root graph and saved with it. Members are SubgraphNodes
/// with this set's id; each one's sub graph is an instance decoded from the
/// stored graph, so every member holds the same nodes under the same ids,
/// and the member edited last is the one the stored graph was encoded from.
/// See SubgraphNode.cloneSetID and Graph.reinstantiateCloneSiblings.
public final class CloneSet: Codable, Identifiable
{
    public let id: UUID
    public internal(set) var name: String

    /// Canonical JSON of the stored graph, keys sorted, so two encodings of
    /// the same design compare equal byte for byte. Nested members inside it
    /// are written as references to their own sets, the way a document is.
    public internal(set) var graphJSON: Data
    {
        didSet { comparableGraph = nil }
    }

    init(id: UUID = UUID(), name: String, graphJSON: Data)
    {
        self.id = id
        self.name = name
        self.graphJSON = graphJSON
    }

    /// The stored graph as a JSON object, for rewriting ids.
    var graphObject: [String: Any] { Self.jsonObject(from: graphJSON) ?? [:] }

    /// The stored graph with every value that is not design left out, the
    /// form a member's design is compared against on every sync and save;
    /// see Graph.designComparableJSON. Made once per stored graph.
    var comparableGraphJSON: Data
    {
        if let comparableGraph { return comparableGraph }
        let comparable = Graph.designComparableJSON(graphJSON)
        comparableGraph = comparable
        return comparable
    }
    private var comparableGraph: Data?

    static func canonicalJSON(_ object: [String: Any]) -> Data
    {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// JSON parsed into Swift-typed values. JSONSerialization's NSNumbers
    /// re-encode 0 and 1 as booleans through AnyCodable, which breaks any
    /// number that goes back through a decoder, so parse this way wherever
    /// the object will be encoded again.
    static func jsonObject(from data: Data) -> [String: Any]?
    {
        (try? JSONDecoder().decode(AnyCodable.self, from: data))?.value as? [String: Any]
    }

    private enum CodingKeys: String, CodingKey
    {
        case id
        case name
        case graph
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        let graph = try container.decode(AnyCodable.self, forKey: .graph).value as? [String: Any] ?? [:]
        self.graphJSON = Self.canonicalJSON(graph)
    }

    public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(AnyCodable(self.graphObject), forKey: .graph)
    }
}

/// A clone set as decoded from a document: nil where the entry cannot be
/// read, so one bad set costs its members' links rather than the document.
struct LossyCloneSet: Decodable
{
    let set: CloneSet?

    init(from decoder: any Decoder) throws
    {
        do { self.set = try CloneSet(from: decoder) }
        catch
        {
            print("Graph: dropping a clone set that cannot be read: \(error.localizedDescription)")
            self.set = nil
        }
    }
}
