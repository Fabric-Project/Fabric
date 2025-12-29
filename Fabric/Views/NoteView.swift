//
//  Untitled.swift
//  Fabric
//
//  Created by Anton Marini on 12/29/25.
//

import Foundation
import SwiftUI
internal import Textual

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
                    .foregroundStyle( .primary )
            }
            else
            {
                TextEditor( text: self.$string)
                    .textEditorStyle( .plain )
                    .foregroundStyle( .primary )
                    .font(Font.system(size: 10).monospaced() )
                    .focusable(true, interactions: .edit)
            }
        }
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
