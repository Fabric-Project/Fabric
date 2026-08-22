import SwiftUI

struct LocalModelNodeSettingsPanel: View {
    let curatedModels: [LocalModelCatalogEntry]
    @Binding var selectedModelID: String
    @Binding var temperature: Float
    @Binding var updateIntervalSeconds: Float
    @Binding var systemPromptOverride: String
    @Binding var chatModeEnabled: Bool
    @Binding var desiredMaxContextTokens: Int
    let effectiveMaxContextTokens: Int
    let runtimeState: LocalModelRuntimeState
    let supportsImageInput: Bool
    let loadModel: (String) -> Void
    let cancelModelOperation: () -> Void
    let clearConversation: () -> Void

    @State private var searchText = ""
    @State private var customModelID = ""

    private var filteredModelGroups: [LocalModelCatalogGroup] {
        LocalModelRuntimeSupport.groupedCatalogEntries(from: self.curatedModels, searchText: self.searchText)
    }

    private var selectedModelIsDownloaded: Bool {
        LocalModelRuntimeSupport.isModelDownloaded(modelID: self.selectedModelID)
    }

    var body: some View {
        
        TabView {
            
            Tab("Configuration", systemImage: "brain")
            {
                ScrollView {
                    LocalModelInferenceSection(
                        temperature: self.$temperature,
                        updateIntervalSeconds: self.$updateIntervalSeconds,
                        systemPromptOverride: self.$systemPromptOverride,
                        chatModeEnabled: self.$chatModeEnabled,
                        desiredMaxContextTokens: self.$desiredMaxContextTokens,
                        effectiveMaxContextTokens: self.effectiveMaxContextTokens,
                        supportsImageInput: self.supportsImageInput,
                        clearConversation: self.clearConversation
                    )
                }
                .scrollIndicators(.hidden)
                .padding()
            }
            
            Tab("Model", systemImage: "gear")
            {
                LocalModelSelectionSection(
                    filteredModelGroups: self.filteredModelGroups,
                    searchText: self.$searchText,
                    selectedModelID: self.$selectedModelID,
                    customModelID: self.$customModelID,
                    selectedModelIsDownloaded: self.selectedModelIsDownloaded,
                    runtimeState: self.runtimeState,
                    loadModel: self.loadModel,
                    cancelModelOperation: self.cancelModelOperation
                )
                .padding()
            }
        }
        .tabViewStyle(.grouped)
        .controlSize(.small)
        .font(.callout)
        
        .onAppear {
            self.syncCustomModelID(with: self.selectedModelID)
        }
        .onChange(of: self.selectedModelID) { _, newValue in
            self.syncCustomModelID(with: newValue)
        }
    }

    private func syncCustomModelID(with modelID: String) {
        if self.curatedModels.contains(where: { $0.id == modelID }) {
            return
        }

        self.customModelID = modelID
    }
}

private struct LocalModelSelectionSection: View {
    let filteredModelGroups: [LocalModelCatalogGroup]
    @Binding var searchText: String
    @Binding var selectedModelID: String
    @Binding var customModelID: String
    let selectedModelIsDownloaded: Bool
    let runtimeState: LocalModelRuntimeState
    let loadModel: (String) -> Void
    let cancelModelOperation: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Search models", text: self.$searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    LocalModelTableHeader()

                    ForEach(self.filteredModelGroups) { group in
                        Text(group.organization)
                            .font(.subheadline)
                            .bold()
                            .padding(.top, 6)
                            .gridCellColumns(3)

                        ForEach(group.models) { model in
                            LocalModelSelectionRow(
                                model: model,
                                isSelected: model.id == self.selectedModelID,
                                selectedModelRuntimeState: self.runtimeState,
                                loadModel: self.loadModel,
                                cancelModelOperation: self.cancelModelOperation
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            VStack(alignment: .leading) {
                Text("Custom Hugging Face Repo")
                    .font(.subheadline)

                HStack {
                    TextField("org/model-name", text: self.$customModelID)
                        .textFieldStyle(.roundedBorder)

                    Button("Load Repo", systemImage: "arrow.down.circle") {
                        let trimmedModelID = self.customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmedModelID.isEmpty == false else { return }
                        self.loadModel(trimmedModelID)
                    }
                }
            }

            VStack(alignment: .leading) {
                Text("Current Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(self.selectedModelID)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Spacer()

                    LocalModelRuntimeStatusLabel(
                        runtimeState: self.runtimeState,
                        isDownloaded: self.selectedModelIsDownloaded
                    )
                }

                if let detail = self.runtimeState.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct LocalModelTableHeader: View {
    var body: some View {
        GridRow {
            Text("Model")
            Text("Size")
                .gridColumnAlignment(.trailing)
            Text("Action")
                .gridColumnAlignment(.leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LocalModelSelectionRow: View {
    let model: LocalModelCatalogEntry
    let isSelected: Bool
    let selectedModelRuntimeState: LocalModelRuntimeState
    let loadModel: (String) -> Void
    let cancelModelOperation: () -> Void

    var body: some View {
        GridRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(self.model.displayName)
                    .lineLimit(1)

                Text(self.model.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Group {
                if let sizeInBytes = self.model.sizeInBytes {
                    Text(sizeInBytes, format: .byteCount(style: .file))
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .monospacedDigit()

            LocalModelRowAction(
                model: self.model,
                runtimeState: self.isSelected ? self.selectedModelRuntimeState : .unloaded,
                isCurrentModel: self.isSelected,
                loadModel: self.loadModel,
                cancelModelOperation: self.cancelModelOperation
            )
        }
        .padding(.vertical, 3)
    }
}

private struct LocalModelRowAction: View {
    let model: LocalModelCatalogEntry
    let runtimeState: LocalModelRuntimeState
    let isCurrentModel: Bool
    let loadModel: (String) -> Void
    let cancelModelOperation: () -> Void

    var body: some View {
        if self.isCurrentModel {
            switch self.runtimeState {
            case .downloading(let progress):
                HStack(spacing: 4) {
                    ProgressView(value: progress)
                        .frame(width: 52)
                    Text(progress, format: .percent.precision(.fractionLength(1)))
                        .font(.caption)
                        .monospacedDigit()
                    Button("Cancel Download", systemImage: "xmark.circle", action: self.cancelModelOperation)
                        .labelStyle(.iconOnly)
                        .help("Cancel download")
                }

            case .loading:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading")
                        .font(.caption)
                    Button("Cancel Loading", systemImage: "xmark.circle", action: self.cancelModelOperation)
                        .labelStyle(.iconOnly)
                        .help("Cancel loading")
                }

            case .ready, .generating:
                Label(self.runtimeState.title, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)

            case .failed:
                Button("Retry", systemImage: "arrow.clockwise") {
                    self.loadModel(self.model.id)
                }

            case .unloaded:
                LocalModelLoadButton(model: self.model, loadModel: self.loadModel)
            }
        } else {
            LocalModelLoadButton(model: self.model, loadModel: self.loadModel)
        }
    }
}

private struct LocalModelLoadButton: View {
    let model: LocalModelCatalogEntry
    let loadModel: (String) -> Void

    var body: some View {
        if self.model.isDownloaded {
            Button("Load", systemImage: "memorychip") {
                self.loadModel(self.model.id)
            }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                self.loadModel(self.model.id)
            }
        }
    }
}

private struct LocalModelRuntimeStatusLabel: View {
    let runtimeState: LocalModelRuntimeState
    let isDownloaded: Bool

    var body: some View {
        switch self.runtimeState {
        case .downloading(let progress):
            HStack {
                ProgressView(value: progress)
                Text(self.runtimeState.title)
            }

        case .loading:
            Label(self.runtimeState.title, systemImage: "hourglass")
                .foregroundStyle(.secondary)

        case .ready:
            Label(self.runtimeState.title, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .generating:
            Label(self.runtimeState.title, systemImage: "waveform")
                .foregroundStyle(.green)

        case .failed:
            Label(self.runtimeState.title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

        case .unloaded:
            if self.isDownloaded {
                Label("Downloaded", systemImage: "internaldrive.fill")
                    .foregroundStyle(.secondary)
            } else {
                Label("Not Downloaded", systemImage: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LocalModelInferenceSection: View {
    @Binding var temperature: Float
    @Binding var updateIntervalSeconds: Float
    @Binding var systemPromptOverride: String
    @Binding var chatModeEnabled: Bool
    @Binding var desiredMaxContextTokens: Int
    let effectiveMaxContextTokens: Int
    let supportsImageInput: Bool
    let clearConversation: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            
            GroupBox("Chat Settings")
            {
                VStack(alignment: .leading) {
                    
                    TextEditor(text: self.$systemPromptOverride)
                        .padding(5)
                        .frame(minHeight: 60, maxHeight: 120)
                        .clipShape( RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.tertiary, lineWidth: 1)
                        }

                    Text(self.supportsImageInput ? "Leave blank to use Fabric's default vision instructions when an image is connected." : "Leave blank to use the default assistant instructions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    
                    HStack(alignment: .top)
                    {
                        VStack(alignment: .leading)
                        {
                            Toggle("Chat Mode", isOn: self.$chatModeEnabled)
                            Text("Enabling chat mode keeps chat history sent to agent. Disabling will clear it and run single-shot prompting.")
                                .font(.subheadline)

                        }
                        
                        Button("Clear Conversation", systemImage: "trash", action: self.clearConversation)
                            .buttonStyle(.borderless)
                        //                    .buttonStyle(.bordered)
                        
                        
                        
                    }
                }
                .padding()
                
            }

            GroupBox("Inference Settings")
            {
                VStack(alignment: .leading) {
                    
//                    HStack
//                    {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(self.temperature, format: .number.precision(.fractionLength(2)))
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: self.$temperature, in: 0.0...2.0)
                        
                        HStack {
                            Text("Update Interval")
                            Spacer()
                            Text(self.updateIntervalSeconds, format: .number.precision(.fractionLength(2)))
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: self.$updateIntervalSeconds, in: 0.05...1.0)
//                    }

                    Stepper(value: self.$desiredMaxContextTokens, in: 256...32_768, step: 256) {
                        VStack(alignment: .leading) {
                            Text("Desired Max Context Tokens")
                            Text("\(self.desiredMaxContextTokens)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Effective Max Context Tokens: \(self.effectiveMaxContextTokens)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
}
