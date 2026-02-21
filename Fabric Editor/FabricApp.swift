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

        Task {
            await FabricEditorMCPServer.shared.startIfEnabled()
        }
    }
    
    
    var body: some Scene {

        DocumentGroup(newDocument: FabricDocument(withTemplate: true) ) { file in
            
            ContentView(document: file.$document)
                .focusedSceneValue(\.document, file.$document)

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
            
            DocumentCommands()
            
            CommandGroup(after: .appInfo)
            {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            
           
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

struct DocumentCommands:Commands
{
    @FocusedBinding(\.document) var document: FabricDocument?

    var body: some Commands {
        CommandGroup(before: .pasteboard)
        {
            Button("Select All Nodes")
            {
                let graph = self.document?.graph.activeSubGraph ?? self.document?.graph
                graph?.selectAllNodes()
                print("Select All")
            }
            .keyboardShortcut(KeyEquivalent("a"), modifiers: .command)
            .disabled( self.document?.graph.nodes.isEmpty ?? true)
        }

        CommandGroup(replacing: .pasteboard)
        {
            let graph = self.document?.graph.activeSubGraph ?? self.document?.graph
            let hasSelection = graph?.nodes.contains(where: { $0.isSelected }) ?? false
            let hasPasteData = NSPasteboard.general.data(forType: Graph.nodeClipboardType) != nil

            Button("Copy")
            {
                guard let graph else { return }
                let selected = graph.nodes.filter { $0.isSelected }
                graph.copyNodesToPasteboard(selected)
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!hasSelection)

            Button("Paste")
            {
                graph?.pasteNodesFromPasteboard()
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!hasPasteData)

            Button("Duplicate")
            {
                guard let graph else { return }
                let selected = graph.nodes.filter { $0.isSelected }
                graph.duplicateNodes(selected)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!hasSelection)
        }
    }
}


struct DocumentFocusedValueKey: FocusedValueKey {
  typealias Value = Binding<FabricDocument>
}

extension FocusedValues
{
    var document: DocumentFocusedValueKey.Value?
    {
        get {
            self[DocumentFocusedValueKey.self]
        }
        set {
            self[DocumentFocusedValueKey.self] = newValue
        }
    }
}


