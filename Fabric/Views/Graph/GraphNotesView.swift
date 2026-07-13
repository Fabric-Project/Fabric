//
//  GraphNotesView.swift
//  Fabric
//

import SwiftUI

struct GraphNotesView: View
{
    let editingContext: GraphCanvasContext
    let geom: GeometryProxy

    var body: some View
    {
        let currentGraph = editingContext.currentGraph

        ForEach(currentGraph.notes) { currentNote in
            NoteView(note: currentNote)
                .offset(-geom.size / 2)
                .offset(x: currentNote.rect.midX, y: currentNote.rect.midY)
                .contextMenu {
                    Button("Delete Note") {
                        currentGraph.deleteNote(currentNote)
                    }
                }
        }
    }
}
