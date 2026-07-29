//
//  Connection.swift
//  Fabric
//
//  Created by Anton Marini on 7/29/26.
//

import SwiftUI
import Satin
internal import AnyCodable

public struct Connection: Codable, Identifiable, Hashable
{
    public let id: UUID
    public let outletPortID: UUID
    public let inletPortID: UUID
    public var active: Bool

    public init(id: UUID = UUID(), outletPortID: UUID, inletPortID: UUID, active: Bool = true)
    {
        self.id = id
        self.outletPortID = outletPortID
        self.inletPortID = inletPortID
        self.active = active
    }
}
