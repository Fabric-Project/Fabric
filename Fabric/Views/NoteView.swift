//
//  Untitled.swift
//  Fabric
//
//  Created by Anton Marini on 12/29/25.
//

import Foundation
import SwiftUI
internal import Textual

// https://github.com/gonzalezreal/textual/issues/6#issuecomment-3705645200
private struct NoteParagraphStyle: StructuredText.ParagraphStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            .textual.blockSpacing(.fontScaled(top: 1.0, bottom: 1.0))
    }
}

private struct NoteHeadingStyle: StructuredText.HeadingStyle
{
    private static let fontScales: [CGFloat] = [1.35, 1.25, 1.15, 1.10, 1.05, 1.0]

    func makeBody(configuration: Configuration) -> some View
    {
        let headingLevel = min(max(configuration.headingLevel, 1), Self.fontScales.count)

        configuration.label
            .textual.fontScale(Self.fontScales[headingLevel - 1])
            .textual.blockSpacing(.fontScaled(top: 0.5, bottom: 0.5))
            .bold()
    }
}

private struct EditorView : View
{
    @Binding var string:String
    @Binding var locked:Bool
    
    var body: some View
    {
        Group
        {
            if self.locked
            {
                StructuredText(markdown:self.string)
                    .textual.paragraphStyle(NoteParagraphStyle())
                    .textual.headingStyle(NoteHeadingStyle())
                    .textual.listItemSpacing(.fontScaled(top: 1.5, bottom: 1.5))
            }
            else
            {
                TextEditor( text: self.$string)
                    .textEditorStyle( .plain )
                    .foregroundStyle( .primary )
                    .scrollIndicators(.hidden)
                    .focusable(true, interactions: .edit)
            }
        }
        .font(.caption)
    }
}

struct NoteView : View
{
    @Bindable var note:Note
    
    @State var locked:Bool = true
    
    var body: some View
    {
        EditorView( string: self.$note.note, locked: self.$locked)
            .padding()
            .frame(width: self.note.rect.size.width, height: self.note.rect.size.height, alignment: .topLeading)
            .background( Color.black.opacity(0.5) )
            .overlay(
                
                ZStack(alignment: .bottomTrailing)
                {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke( Color.gray.opacity(0.5), lineWidth: 1 )
                        .frame(width: self.note.rect.size.width, height: self.note.rect.size.height, alignment: .topLeading)
                    
                    Button("", systemImage: self.locked ? "lock.fill" : "lock.open.fill") {
                        self.locked.toggle( )
                    }
                    .frame(width: 20, height: 20)
                    .buttonStyle(.borderless)
                    .offset(y: -self.note.rect.size.height + 20)
                    
                    Rectangle()
                        .fill( Color.gray.opacity(0.25))
                        .stroke( Color.gray.opacity(0.25), lineWidth: 1 )
                        .frame(width: 25, height:25)
                        .gesture(self.locked ? nil : DragGesture()
                            .onChanged { value in
                                
                                self.note.rect.size.width += value.translation.width
                                self.note.rect.size.height += value.translation.height
                                
                                self.note.rect.size.width = max(120, self.note.rect.size.width)
                                self.note.rect.size.height = max(60, self.note.rect.size.height)
                            }
                        )
                        .opacity(self.locked ? 0 : 1)
                }
            )
            .clipShape( RoundedRectangle(cornerRadius: 15) )
            .gesture(self.locked ? nil : DragGesture()
                .onChanged { value in
                                        
                    self.note.rect.origin.x += value.translation.width
                    self.note.rect.origin.y += value.translation.height
                }
               
            )

    }
}
