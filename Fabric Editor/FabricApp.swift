//
//  FabricApp.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Fabric
import AppKit



@main
struct FabricApp: App {
    var body: some Scene {

        DocumentGroup(newDocument: FabricDocument() ) { file in
            
            ContentView(document: file.$document)
                .onAppear {
                    // THIS SHIT HAS TO BE ON MAIN THREAD FOR APPKIT
                    file.document.setupOutputWindow()
                }
                .onDisappear {
                    // THIS SHIT HAS TO BE ON MAIN THREAD FOR APPKIT
                    file.document.closeOutputWindow()
                }
                
        }
        .commands {
            AboutCommands()
        }
        
        Window("About Fabric Editor", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Fabric Editor") {
                openWindow(id: "about")
            }
        }
    }
}
