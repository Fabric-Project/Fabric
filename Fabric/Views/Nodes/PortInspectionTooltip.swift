//
//  PortInspectionTooltip.swift
//  Fabric
//

import SwiftUI

struct PortInspectionTooltip: ViewModifier
{
    let port: Port

    @State private var snapshot: String = ""

    func body(content: Content) -> some View
    {
        content
            .help(snapshot)
            .onHover { hovering in
                if hovering
                {
                    snapshot = port.inspectionTooltip
                }
            }
    }
}
