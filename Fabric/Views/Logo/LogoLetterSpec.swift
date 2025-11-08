//
//  LogoLetterSpec.swift
//  Fabric
//
//  Created by Toby Harris on 11/8/25.
//

import Foundation

/// Letter specifications for the FABRIC wordmark.
extension LogoLetterSpec {
    /// Letter "F" composed of a vertical stem and two right-side nodes.
    static let f = LogoLetterSpec(
        symbol: "F",
        leftColumn: LogoColumn(items: [
            .node
        ]),
        rightColumn: LogoColumn(items: [
            .node,
            .gap,
            .node,
            .gap,
            .gap
        ]),
        connectors: [
            LogoConnector(leftIndex: 0, rightIndex: 0),
            LogoConnector(leftIndex: 2, rightIndex: 2)
        ]
    )

    /// Letter "A" featuring mirrored columns connected at multiple heights.
    static let a = LogoLetterSpec(
        symbol: "A",
        leftColumn: LogoColumn(items: [
            .node
        ]),
        rightColumn: LogoColumn(items: [
            .node
        ]),
        connectors: [
            LogoConnector(leftIndex: 0, rightIndex: 0),
            LogoConnector(leftIndex: 2, rightIndex: 2)
        ]
    )

    /// Letter "B" with a solid stem and stacked right-side nodes.
    static let b = LogoLetterSpec(
        symbol: "B",
        leftColumn: LogoColumn(items: [
            .node
        ]),
        rightColumn: LogoColumn(items: [
            .node,
            .node
        ]),
        connectors: [
            LogoConnector(leftIndex: 0, rightIndex: 0),
            LogoConnector(leftIndex: 1, rightIndex: 1),
            LogoConnector(leftIndex: 3, rightIndex: 3),
            LogoConnector(leftIndex: 4, rightIndex: 4),
        ]
    )

    /// Letter "R" reusing the "B" stem with a lower diagonal connector.
    static let r = LogoLetterSpec(
        symbol: "R",
        leftColumn: LogoColumn(items: [
            .node
        ]),
        rightColumn: LogoColumn(items: [
            .node,
            .node
        ]),
        connectors: [
            LogoConnector(leftIndex: 0, rightIndex: 0),
            LogoConnector(leftIndex: 1, rightIndex: 1),
            LogoConnector(leftIndex: 2, rightIndex: 3),
        ]
    )

    /// Letter "I" consisting of a single column with no connectors.
    static let i = LogoLetterSpec(
        symbol: "I",
        leftColumn: LogoColumn(items: [
            .node
        ]),
        rightColumn: nil,
        connectors: []
    )

    /// Letter "C" formed by a vertical stem and a matching right column for top/bottom nodes.
    static let c = LogoLetterSpec(
        symbol: "C",
        leftColumn: LogoColumn(items: [
            .node
        ]),
        rightColumn: LogoColumn(items: [
            .node,
            .gap,
            .gap,
            .gap,
            .node
        ]),
        connectors: [
            LogoConnector(leftIndex: 0, rightIndex: 0),
            LogoConnector(leftIndex: 4, rightIndex: 4)
        ]
    )

    /// All letter specifications used to render the complete FABRIC wordmark.
    static let all: [LogoLetterSpec] = [.f, .a, .b, .r, .i, .c]

    /// Maximum number of items present in any column across all letter specifications.
    static let maxColumnItemCount: Int = {
        all.flatMap { spec in
            [spec.leftColumn, spec.rightColumn].compactMap { $0 }
        }
        .map { $0.items.count }
        .max() ?? 1
    }()
}
