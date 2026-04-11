//
//  OutputPreviewView.swift
//  Fabric Editor
//
//  Created by Claude on 4/11/26.
//

import SwiftUI
import Fabric

/// Wraps the CAMetalDisplayLinkRenderer (AppKit) for embedding in the SwiftUI editor canvas.
struct OutputPreviewView: NSViewRepresentable {
    let graph: Graph

    func makeNSView(context: Context) -> CAMetalDisplayLinkRenderer {
        CAMetalDisplayLinkRenderer(graph: graph)
    }

    func updateNSView(_ nsView: CAMetalDisplayLinkRenderer, context: Context) {}

    static func dismantleNSView(_ nsView: CAMetalDisplayLinkRenderer, coordinator: ()) {
        nsView.teardown()
    }
}
