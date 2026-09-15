//
//  CloneSet.swift
//  Fabric
//
//  Created by Claude on 9/10/26.
//

import Foundation
internal import AnyCodable

/// A clone set: the template every member is kept identical to, held as
/// data, plus the set's name. Owned by the document's root graph and saved
/// with it. Members refer to it by id and keep a record mapping the
/// template's ids to their own; see SubgraphNode.cloneSetID.
///
/// The template is the encoded form of a member's sub graph with every id
/// rewritten to the template's own ids. It is refreshed from whichever member
/// was edited last, materialised when a member is created without a live
/// source, and is the form that can be stored or shared outside the document.
public final class CloneSet: Codable, Identifiable
{
    public let id: UUID
    public internal(set) var name: String

    /// The registered type of the set's members (a Subgraph, Iterator, ...),
    /// as the document spells it, so a member can be made from the template
    /// alone.
    public let memberNodeType: String

    /// Canonical JSON of the template graph, keys sorted, so two templates
    /// with the same design compare equal byte for byte.
    public internal(set) var templateJSON: Data

    init(id: UUID = UUID(), name: String, memberNodeType: String, templateJSON: Data)
    {
        self.id = id
        self.name = name
        self.memberNodeType = memberNodeType
        self.templateJSON = templateJSON
    }

    /// The template as a JSON object, for rewriting ids.
    var templateObject: [String: Any]
    {
        get { Self.jsonObject(from: templateJSON) ?? [:] }
        set { templateJSON = Self.canonicalJSON(newValue) }
    }

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
        case memberNodeType
        case template
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.memberNodeType = try container.decode(String.self, forKey: .memberNodeType)
        let template = try container.decode(AnyCodable.self, forKey: .template).value as? [String: Any] ?? [:]
        self.templateJSON = Self.canonicalJSON(template)
    }

    public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.memberNodeType, forKey: .memberNodeType)
        try container.encode(AnyCodable(self.templateObject), forKey: .template)
    }
}
