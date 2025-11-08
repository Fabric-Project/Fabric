//
//  LogoTypes.swift
//  Fabric
//
//  Created by Toby Harris on 11/8/25.
//

import Foundation

/// An item within a column that is either a rendered node or an intentional gap.
enum LogoColumnItem {
    case gap
    case node
}

extension LogoColumnItem {
    /// Indicates whether this column item represents a rendered node square.
    var isNode: Bool {
        if case .node = self { return true }
        return false
    }
}

/// Collection of column items representing a vertical stack for a glyph column.
struct LogoColumn {
    var items: [LogoColumnItem]
}

/// Describes a connector line joining index positions between two columns.
struct LogoConnector {
    var leftIndex: Int
    var rightIndex: Int
}

/// Specification describing how to render a single letter in the Fabric logo.
///
/// Each glyph is composed of one or two vertical columns populated with nodes and gaps,
/// plus an optional set of connectors that link node indices across the two columns.
struct LogoLetterSpec {
    /// The character represented by this glyph specification.
    var symbol: Character
    /// Column data for the left side of the letter. This column is always present.
    var leftColumn: LogoColumn
    /// Optional column data for the right side of the letter.
    var rightColumn: LogoColumn?
    /// Connectors that bridge node indices between the left and right columns.
    var connectors: [LogoConnector]
}
