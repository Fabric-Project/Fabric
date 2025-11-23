//
//  FabricApp.swift
//  Fabric
//
//  Created by Anton Marini on 4/24/25.
//

import SwiftUI
import Fabric
import AppKit
import Sparkle


@main
struct FabricApp: App {
    
    private let updaterController: SPUStandardUpdaterController

    init()
    {
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    
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
            CommandGroup(after: .appInfo)
            {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            ViewCommands()
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

struct ViewCommands: Commands {
    @FocusedValue(\.centerOnSelectedNode) private var centerOnSelectedNode: (() -> Void)?
    
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Center on Selected Node") {
                centerOnSelectedNode?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(centerOnSelectedNode == nil)
        }
    }
}

// FocusedValue key for center on selected node action
struct CenterOnSelectedNodeKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var centerOnSelectedNode: CenterOnSelectedNodeKey.Value? {
        get { self[CenterOnSelectedNodeKey.self] }
        set { self[CenterOnSelectedNodeKey.self] = newValue }
    }
}
