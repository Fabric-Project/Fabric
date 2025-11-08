//
//  FabricLetterSpec.swift
//  Fabric
//
//  Created by Toby Harris on 11/8/25.
//

import Foundation

/// Specification describing how to render a single letter in the Fabric logo.
///
/// Each glyph is composed of one or two vertical columns populated with nodes and gaps,
/// plus an optional set of connectors that link node indices across the two columns.
struct FabricLetterSpec {
    /// The character represented by this glyph specification.
    var symbol: Character
    /// Column data for the left side of the letter. This column is always present.
    var leftColumn: FabricColumn
    /// Optional column data for the right side of the letter.
    var rightColumn: FabricColumn?
    /// Connectors that bridge node indices between the left and right columns.
    var connectors: [FabricConnector]

    /// Letter "F" composed of a vertical stem and two right-side nodes.
    static let f = FabricLetterSpec(
        symbol: "F",
        leftColumn: FabricColumn(items: [
            .node
        ]),
        rightColumn: FabricColumn(items: [
            .node,
            .gap,
            .node,
            .gap,
            .gap
        ]),
        connectors: [
            FabricConnector(leftIndex: 0, rightIndex: 0),
            FabricConnector(leftIndex: 2, rightIndex: 2)
        ]
    )

    /// Letter "A" featuring mirrored columns connected at multiple heights.
    static let a = FabricLetterSpec(
        symbol: "A",
        leftColumn: FabricColumn(items: [
            .node
        ]),
        rightColumn: FabricColumn(items: [
            .node
        ]),
        connectors: [
            FabricConnector(leftIndex: 0, rightIndex: 0),
            FabricConnector(leftIndex: 2, rightIndex: 2)
        ]
    )

    /// Letter "B" with a solid stem and stacked right-side nodes.
    static let b = FabricLetterSpec(
        symbol: "B",
        leftColumn: FabricColumn(items: [
            .node
        ]),
        rightColumn: FabricColumn(items: [
            .node,
            .node
        ]),
        connectors: [
            FabricConnector(leftIndex: 0, rightIndex: 0),
            FabricConnector(leftIndex: 1, rightIndex: 1),
            FabricConnector(leftIndex: 3, rightIndex: 3),
            FabricConnector(leftIndex: 4, rightIndex: 4),
        ]
    )

    /// Letter "R" reusing the "B" stem with a lower diagonal connector.
    static let r = FabricLetterSpec(
        symbol: "R",
        leftColumn: FabricColumn(items: [
            .node
        ]),
        rightColumn: FabricColumn(items: [
            .node,
            .node
        ]),
        connectors: [
            FabricConnector(leftIndex: 0, rightIndex: 0),
            FabricConnector(leftIndex: 1, rightIndex: 1),
            FabricConnector(leftIndex: 2, rightIndex: 3),
        ]
    )

    /// Letter "I" consisting of a single column with no connectors.
    static let i = FabricLetterSpec(
        symbol: "I",
        leftColumn: FabricColumn(items: [
            .node
        ]),
        rightColumn: nil,
        connectors: []
    )

    /// Letter "C" formed by a vertical stem and a matching right column for top/bottom nodes.
    static let c = FabricLetterSpec(
        symbol: "C",
        leftColumn: FabricColumn(items: [
            .node
        ]),
        rightColumn: FabricColumn(items: [
            .node,
            .gap,
            .gap,
            .gap,
            .node
        ]),
        connectors: [
            FabricConnector(leftIndex: 0, rightIndex: 0),
            FabricConnector(leftIndex: 4, rightIndex: 4)
        ]
    )

    /// All letter specifications used to render the complete FABRIC wordmark.
    static let all: [FabricLetterSpec] = [.f, .a, .b, .r, .i, .c]

    /// Maximum number of items present in any column across all letter specifications.
    static let maxColumnItemCount: Int = {
        all.flatMap { spec in
            [spec.leftColumn, spec.rightColumn].compactMap { $0 }
        }
        .map { $0.items.count }
        .max() ?? 1
    }()
}
