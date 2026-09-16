//
//  NodeStatus.swift
//  Fabric
//
//  Created by Toby Harris on 9/9/26.
//

import Foundation

/// Something a node has to tell the person looking at it, shown as a glyph
/// at the trailing edge of its title with the message on hover. Nodes report
/// statuses through `Node.deriveStatuses()`; the view layer decides how each
/// case looks. The set of cases is the engine's: a node author who needs
/// another meaning asks for a case, so every node then says it the same way.
///
/// Statuses order by severity, so a node reporting several shows the glyph
/// of the most severe, an error over a warning, and lists them all on hover.
public enum NodeStatus: Sendable, Equatable, Comparable, CustomStringConvertible
{
    /// The node cannot run: a parse failure, later an execution failure.
    case error(String)
    /// The node runs, but something wants looking at.
    case warning(String)

    public var message: String
    {
        switch self
        {
        case .error(let message), .warning(let message): message
        }
    }

    /// The kind, as the tooltip names it.
    public var kind: String
    {
        switch self
        {
        case .error: "Error"
        case .warning: "Warning"
        }
    }

    /// The text shown on hover: the kind, then the message.
    public var description: String { "\(kind): \(message)" }

    private var severity: Int
    {
        switch self
        {
        case .warning: 1
        case .error: 2
        }
    }

    // Severity orders the cases and the message breaks ties. Without the
    // tie-break two statuses of one severity compare neither <, > nor ==, and
    // a sort of them is then free to return either order.
    public static func < (lhs: NodeStatus, rhs: NodeStatus) -> Bool
    {
        (lhs.severity, lhs.message) < (rhs.severity, rhs.message)
    }
}
