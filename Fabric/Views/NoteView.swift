//
//  Untitled.swift
//  Fabric
//
//  Created by Anton Marini on 12/29/25.
//

import Foundation
import SwiftUI

struct NoteView : View
{
    @Bindable var note:Note
    
    var body: some View
    {
        TextEditor( text: self.$note.note)
            .textEditorStyle( .plain )
        //        Text( LocalizedStringKey(self.note.note) )
            .focusable(true)
            .font(Font.system(size: 10).monospaced() )
            .padding()
            .frame(width: self.note.rect.size.width, height: self.note.rect.size.height, alignment: .topLeading)
            .background( Color.black.opacity(0.5) )
            .foregroundStyle( .primary )
            .overlay(
                ZStack(alignment: .bottomTrailing)
                {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke( Color.gray, lineWidth: 1 )
//                        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .miter, miterLimit: 0, dash: [5, 25], dashPhase: 0) )
//                        .foregroundStyle( Color.gray )
                        .frame(width: self.note.rect.size.width, height: self.note.rect.size.height, alignment: .topLeading)
                    
                    Rectangle()
                        .fill( Color.gray.opacity(0.5))
                        .stroke( Color.gray.opacity(0.5), lineWidth: 1 )
                        .frame(width: 15, height:15)
                        .gesture(DragGesture()
                            .onChanged { value in
                                
                                self.note.rect.size.width += value.translation.width
                                self.note.rect.size.height += value.translation.height
                                
                                self.note.rect.size.width = max(120, self.note.rect.size.width)
                                self.note.rect.size.height = max(60, self.note.rect.size.height)
                                
                                print("Resize ")
                            }
                            .onEnded { value in
                                print("Drag Stopped")
                            }
                        )
                }
            )
            .clipShape( RoundedRectangle(cornerRadius: 15) )
            .gesture(DragGesture()
                .onChanged { value in
                    self.note.rect.origin.x += value.translation.width
                    self.note.rect.origin.y += value.translation.height
                    
                    print("Reposition")
                }
                .onEnded { value in
                    print("Reposition Stopped")
                }
            )
            
    }
}
