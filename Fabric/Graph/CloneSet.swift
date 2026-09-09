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

    /// Canonical JSON of the template graph, keys sorted, so two templates
    /// with the same design compare equal byte for byte.
    public internal(set) var templateJSON: Data

    init(id: UUID = UUID(), name: String, templateJSON: Data)
    {
        self.id = id
        self.name = name
        self.templateJSON = templateJSON
    }

    /// The template as a JSON object, for rewriting ids.
    var templateObject: [String: Any]
    {
        get
        {
            (try? JSONSerialization.jsonObject(with: templateJSON) as? [String: Any]) ?? [:]
        }
        set
        {
            templateJSON = Self.canonicalJSON(newValue)
        }
    }

    static func canonicalJSON(_ object: [String: Any]) -> Data
    {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    private enum CodingKeys: String, CodingKey
    {
        case id
        case name
        case template
    }

    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        let template = try container.decode(AnyCodable.self, forKey: .template).value as? [String: Any] ?? [:]
        self.templateJSON = Self.canonicalJSON(template)
    }

    public func encode(to encoder: any Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(AnyCodable(self.templateObject), forKey: .template)
    }
}
