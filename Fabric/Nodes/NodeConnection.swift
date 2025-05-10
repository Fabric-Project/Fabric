//
//  NodeConnection.swift
//  v
//
//  Created by Anton Marini on 5/17/24.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers


struct OutletData : Codable
{
    let portID: UUID
    init(portID: UUID)
    {
        self.portID = portID
    }
}

extension OutletData :Transferable
{
    static var transferRepresentation: some TransferRepresentation 
    {
        CodableRepresentation(contentType: .outletData)
    }
}

extension UTType 
{
    static var outletData: UTType { UTType(exportedAs: "info.vade.v.outletData") }
}
