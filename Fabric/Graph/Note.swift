//
//  Note.swift
//  Fabric
//
//  Created by Anton Marini on 12/29/25.
//

import Foundation
import SwiftUI

@Observable public class Note : Codable, Hashable, Identifiable, Equatable
{
    public let id = UUID()
    public var note:String
    public var rect:CGRect
//    let color:Color // do we actually care?

    enum CodingKeys: CodingKey
    {
        case id
        case note
        case rect
    }
    
    public static func  == (lhs: Note, rhs: Note) -> Bool
    {
        return lhs.id == rhs.id && lhs.note == rhs.note && lhs.rect == rhs.rect
    }
    
    public init(note: String, rect: CGRect)
    {
        self.note = note
        self.rect = rect
    }
    
    required public init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.note = try container.decode(String.self, forKey: .note)
        self.rect = try container.decode(CGRect.self, forKey: .rect)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(note, forKey: .note)
        try container.encode(rect, forKey: .rect)
    }
    
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
        hasher.combine(note)
        hasher.combine(rect)
    }
}
