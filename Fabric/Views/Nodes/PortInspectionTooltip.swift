//
//  PortInspectionTooltip.swift
//  Fabric
//

import SwiftUI

/// Hover-driven help tooltip carrying the port's current value.
///
/// `.onHover` fires only on cursor enter/exit — when not hovering this
/// modifier does no work. On hover-enter we snapshot
/// `port.inspectionTooltip` into local state; AppKit reads the
/// underlying `toolTip` at show-time, so each fresh hover surfaces an
/// up-to-date value without polling.
struct PortInspectionTooltip: ViewModifier
{
    let port: Port

    @State private var snapshot: String = ""

    func body(content: Content) -> some View
    {
        content
            .help(snapshot)
            .onHover { hovering in
                if hovering { snapshot = port.inspectionTooltip }
            }
    }
}
