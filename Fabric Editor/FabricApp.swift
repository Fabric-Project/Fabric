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
    @FocusedValue(\.editingContext) var editingContext: CanvasEditingContext?
    @FocusedBinding(\.editorInputFocus) var editorInputFocus: FabricEditorInputFocus?

    private var isCanvasFocused: Bool {
        self.editorInputFocus == .canvas
    }

    var body: some Commands {

        CommandGroup(replacing: .pasteboard)
        {
            let graph = editingContext?.activeGraph
            let hasSelection = graph?.nodes.contains(where: { $0.isSelected }) ?? false
            let hasPasteData = NSPasteboard.general.data(forType: Graph.nodeClipboardType) != nil

            Button("Copy")
            {
                if self.isCanvasFocused {
                    guard let graph else { return }
                    let selected = graph.nodes.filter { $0.isSelected }
                    graph.copyNodesToPasteboard(selected)
                }
                else
                {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(self.isCanvasFocused ? !hasSelection : false)

            Button("Paste")
            {
                if self.isCanvasFocused {
                    graph?.pasteNodesFromPasteboard()
                }
                else
                {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(self.isCanvasFocused ? !hasPasteData : false)

            Button("Duplicate")
            {
                guard let graph else { return }
                let selected = graph.nodes.filter { $0.isSelected }
                graph.duplicateNodes(selected)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(self.isCanvasFocused ? !hasSelection : true)
        }

        CommandGroup(after: .pasteboard)
        {
            Button("Select All Nodes")
            {
                if self.isCanvasFocused {
                    editingContext?.activeGraph.selectAllNodes()
                }
                else
                {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut(KeyEquivalent("a"), modifiers: .command)
            .disabled(self.isCanvasFocused ? (editingContext?.activeGraph.nodes.isEmpty ?? true) : false)
        }
    }
}


struct DocumentFocusedValueKey: FocusedValueKey {
  typealias Value = Binding<FabricDocument>
}

struct EditorInputFocusValueKey: FocusedValueKey {
    typealias Value = Binding<FabricEditorInputFocus>
}

extension FocusedValues
{
    @Entry var editingContext: CanvasEditingContext? = nil

    var document: DocumentFocusedValueKey.Value?
    {
        get {
            self[DocumentFocusedValueKey.self]
        }
        set {
            self[DocumentFocusedValueKey.self] = newValue
        }
    }

    var editorInputFocus: EditorInputFocusValueKey.Value?
    {
        get {
            self[EditorInputFocusValueKey.self]
        }
        set {
            self[EditorInputFocusValueKey.self] = newValue
        }
    }
}


