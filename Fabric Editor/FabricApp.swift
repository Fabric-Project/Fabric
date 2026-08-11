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

        }
        .commands {
            AboutCommands()

            DocumentCommands()

            ViewCommands()

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
    @FocusedValue(\.editorFocusTarget) var editorFocusTarget: Binding<FabricEditorFocusTarget?>?

    private var activeDocument: FabricDocument? {
        self.document ?? ActiveFabricDocumentStore.shared.activeDocument
    }

    /// Derived from real keyboard focus: false whenever any text field
    /// (node settings, rename, registry search) is being edited, so the
    /// pasteboard commands below route to the field editor instead.
    private var isCanvasFocused: Bool {
        self.editorFocusTarget?.wrappedValue == .canvas
    }

    var body: some Commands {

        CommandGroup(replacing: .pasteboard)
        {
            let graph = self.document?.editingContext.currentGraph
            let hasSelection = !(graph?.selectedNodes.isEmpty ?? true)
            let hasPasteData = NSPasteboard.general.data(forType: Graph.nodeClipboardType) != nil

            Button("Copy")
            {
                if self.isCanvasFocused {
                    guard let graph else { return }
                    graph.copyNodesToPasteboard(graph.selectedNodes)
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
                graph.duplicateNodes(graph.selectedNodes)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(self.isCanvasFocused ? !hasSelection : true)
        }

        CommandGroup(after: .pasteboard)
        {
            Button("Select All Nodes")
            {
                if self.isCanvasFocused
                {
                    self.document?.editingContext.currentGraph.selectAllNodes()
                }
                else
                {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut(KeyEquivalent("a"), modifiers: .command)
            .disabled(self.isCanvasFocused ? (self.document?.editingContext.currentGraph.nodes.isEmpty ?? true) : false)

            Button("Find Nodes")
            {
                self.editorFocusTarget?.wrappedValue = .registrySearch
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(self.isCanvasFocused ? (self.document?.editingContext.currentGraph.nodes.isEmpty ?? true) : false)
        }

        CommandGroup(after: .saveItem)
        {
            Divider() // Optional: separates the submenu from system items
            
            Menu("Export")
            {
                Button("Image…")
                {
                    self.activeDocument?.exportSnapshotImage()
                }
                .disabled(self.activeDocument == nil)
                
                Button("Movie…")
                {
                    self.activeDocument?.exportMovie()
                }
                .disabled(self.activeDocument == nil)
            }
        }
    }
}


struct ViewCommands: Commands {
    @FocusedBinding(\.document) var document: FabricDocument?

    /// The store tracks whichever window last became active — editor or
    /// output — and is observable, so menus re-evaluate on window switches.
    /// The focused-document binding can go stale while an AppKit output
    /// window is key, so it is only a fallback.
    private var activeDocument: FabricDocument? {
        ActiveFabricDocumentStore.shared.activeDocument ?? self.document
    }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            let graph = document?.editingContext.currentGraph
            let settingsViewModels = graph.map { g in
                g.selectedNodes.map { g.viewModel(for: $0) }.filter { $0.providesSettingsView() }
            } ?? []
            let allOpen = !settingsViewModels.isEmpty && settingsViewModels.allSatisfy(\.showSettings)

            Button(allOpen ? "Hide Node Settings" : "Show Node Settings") {
                for viewModel in settingsViewModels {
                    viewModel.showSettings = !allOpen
                }
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(settingsViewModels.isEmpty)

            Divider()

            Button("Auto Layout Graph") {
                // Operate on the graph the user is currently looking
                // at (a subgraph if they've drilled in), not the
                // document's root.
                document?.editingContext.currentGraph.autoLayout()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(document == nil)

            Divider()

            // Read the mode here in the body, not inside the binding's
            // getter, so observation registers it and the menu re-evaluates
            // when the active document or its mode changes.
            let outputPresenter = self.activeDocument?.outputPresenter
            let outputMode = outputPresenter?.mode ?? .separateWindow

            Menu("Output") {
                Picker("Destination", selection: Binding(
                    get: { outputMode },
                    set: { outputPresenter?.mode = $0 }
                )) {
                    Text("In-Editor").tag(OutputPresentationMode.editorCanvas)
                    Text("Window").tag(OutputPresentationMode.separateWindow)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .disabled(outputPresenter == nil)

            Divider()
        }
    }
}

struct DocumentFocusedValueKey: FocusedValueKey {
  typealias Value = Binding<FabricDocument>
}

struct EditorFocusTargetValueKey: FocusedValueKey {
    typealias Value = Binding<FabricEditorFocusTarget?>
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

    /// A read/write window onto ContentView's `@FocusState` — the editor's
    /// single keyboard-focus authority.
    var editorFocusTarget: EditorFocusTargetValueKey.Value?
    {
        get {
            self[EditorFocusTargetValueKey.self]
        }
        set {
            self[EditorFocusTargetValueKey.self] = newValue
        }
    }
}
