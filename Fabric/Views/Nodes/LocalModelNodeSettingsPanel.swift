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
    let activityText: String
    let supportsImageInput: Bool
    let clearConversation: () -> Void

    @State private var searchText = ""
    @State private var customModelID = ""

    private var filteredModelGroups: [LocalModelCatalogGroup] {
        LocalModelRuntimeSupport.groupedCatalogEntries(from: self.curatedModels, searchText: self.searchText)
    }

    private var selectedModelIsCurated: Bool {
        self.curatedModels.contains(where: { $0.id == self.selectedModelID })
    }

    private var selectedModelIsDownloaded: Bool {
        LocalModelRuntimeSupport.isModelDownloaded(modelID: self.selectedModelID)
    }

    private var selectedModelOrganization: String {
        self.selectedModelID.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "Custom"
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
                    selectedModelIsCurated: self.selectedModelIsCurated,
                    selectedModelIsDownloaded: self.selectedModelIsDownloaded,
                    selectedModelOrganization: self.selectedModelOrganization,
                    activityText: self.activityText
                )
                .padding()
            }
        }
        .tabViewStyle(.grouped)
        
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
    let selectedModelIsCurated: Bool
    let selectedModelIsDownloaded: Bool
    let selectedModelOrganization: String
    let activityText: String

    var body: some View {
        
        VStack(alignment: .leading) {

            Menu("Model:") {
                
                
                TextField("Search models", text: self.$searchText)
//                               .textFieldStyle(.roundedBorder)
                
                ForEach(self.filteredModelGroups) { group in
                    
                    ForEach(group.models) { model in
                        
                        LocalModelSelectionRow(
                            model: model,
                            isSelected: model.id == self.selectedModelID
                        ) {
                            self.selectedModelID = model.id
                        }
                        
                        Divider()
                        
                    }
                }
            }
            
            VStack(alignment: .leading) {
                Text("Custom Hugging Face Repo")
                    .font(.subheadline)

                HStack {
                    TextField("org/model-name", text: self.$customModelID)
                        .textFieldStyle(.roundedBorder)

                    Button("Use Repo") {
                        let trimmedModelID = self.customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmedModelID.isEmpty == false else { return }
                        self.selectedModelID = trimmedModelID
                    }
                }
            }
            .padding(.top, 8)

            VStack(alignment: .leading) {
                
                Text("Current Model:")
                
                HStack {
                    Text(self.selectedModelID)
                        .textSelection(.enabled)

                    Spacer()

                    if self.selectedModelIsDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.green)
                    }
                }

                Text(self.selectedModelIsCurated ? "Curated model from \(self.selectedModelOrganization)." : "Custom repo ID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if self.activityText.isEmpty == false {
                    Text(self.activityText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct LocalModelSelectionRow: View {
    let model: LocalModelCatalogEntry
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(self.model.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(self.model.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if self.model.isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if self.isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
//            .contentShape(.rect)
//            .padding(.vertical, 4)
//            .padding(.horizontal, 8)
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .background(self.isSelected ? Color.accentColor.opacity(0.12) : .clear)
//            .clipShape(.rect(cornerRadius: 8))
        }
//        .buttonStyle(.plain)
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
