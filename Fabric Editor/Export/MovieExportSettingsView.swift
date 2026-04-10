//
//  MovieExportSettingsView.swift
//  Fabric Editor
//
//  Created by Codex on 4/8/26.
//

import SwiftUI

struct MovieExportConfiguration {
    let startTime: TimeInterval
    let duration: TimeInterval
    let size: (width: Int, height: Int)
    let frameRate: Double
    let codec: GraphMovieExportCodec
}

struct MovieExportSettings {
    let startTime: TimeInterval
    let duration: TimeInterval
}

enum MovieExportResolutionPreset: String, CaseIterable, Identifiable {
    case hd720
    case hd1080
    case qhd1440
    case uhd4K
    case custom

    var id: String { self.rawValue }

    func title() -> String {
        switch self {
        case .hd720:
            return "720p"
        case .hd1080:
            return "1080p"
        case .qhd1440:
            return "qHD"
        case .uhd4K:
            return "4K"
        case .custom:
            return "Custom"
        }
    }

    func size() -> (width: Int, height: Int)? {
        switch self {
       case .hd720:
            return (1280, 720)
        case .hd1080:
            return (1920, 1080)
        case .qhd1440:
            return (2560, 1440)
        case .uhd4K:
            return (3840, 2160)
        case .custom:
            return nil
        }
    }
}

enum MovieExportFrameRatePreset: String, CaseIterable, Identifiable {
    case fps23_976
    case fps24
    case fps25
    case fps29_97
    case fps30
    case fps50
    case fps59_94
    case fps60
    case fps120

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .fps23_976:
            return "23.976 fps"
        case .fps24:
            return "24 fps"
        case .fps25:
            return "25 fps"
        case .fps29_97:
            return "29.97 fps"
        case .fps30:
            return "30 fps"
        case .fps50:
            return "50 fps"
        case .fps59_94:
            return "59.94 fps"
        case .fps60:
            return "60 fps"
        case .fps120:
            return "120 fps"
        }
    }

    var frameRate: Double {
        switch self {
        case .fps23_976:
            return 23.976
        case .fps24:
            return 24
        case .fps25:
            return 25
        case .fps29_97:
            return 29.97
        case .fps30:
            return 30
        case .fps50:
            return 50
        case .fps59_94:
            return 59.94
        case .fps60:
            return 60
        case .fps120:
            return 120
        }
    }
}

enum MovieExportSheetPhase {
    case settings
    case exporting
}

@MainActor
@Observable final class MovieExportSettingsViewModel {
    let availableResolutionPresets: [MovieExportResolutionPreset]

    var startTime: Double
    var duration: Double
    var selectedResolutionPreset: MovieExportResolutionPreset {
        didSet {
            self.applyResolutionPreset()
        }
    }
    var width: Int
    var height: Int
    var frameRatePreset: MovieExportFrameRatePreset
    var codec: GraphMovieExportCodec

    init(initialSettings: MovieExportSettings) {
        self.availableResolutionPresets = MovieExportResolutionPreset.allCases
        self.startTime = initialSettings.startTime
        self.duration = initialSettings.duration
        self.selectedResolutionPreset = .hd1080
        self.width =  1920
        self.height =  1080
        self.frameRatePreset = .fps30
        self.codec = .h264
        self.applyResolutionPreset()
    }

    var isUsingCustomResolution: Bool {
        self.selectedResolutionPreset == .custom
    }

    var canExport: Bool {
        self.startTime >= 0 &&
        self.duration > 0 &&
        self.width > 0 &&
        self.height > 0 &&
        self.width.isMultiple(of: 2) &&
        self.height.isMultiple(of: 2) &&
        self.frameRatePreset.frameRate > 0
    }

    var validationMessage: String? {
        if self.duration <= 0 {
            return "Duration must be greater than zero."
        }

        if self.width <= 0 || self.height <= 0 {
            return "Resolution must be greater than zero."
        }

        if !self.width.isMultiple(of: 2) || !self.height.isMultiple(of: 2) {
            return "Width and height must be even numbers."
        }

        if self.frameRatePreset.frameRate <= 0 {
            return "Frame rate must be greater than zero."
        }

        return nil
    }

    func makeConfiguration() -> MovieExportConfiguration {
        MovieExportConfiguration(
            startTime: self.startTime,
            duration: self.duration,
            size: (width: self.width, height: self.height),
            frameRate: self.frameRatePreset.frameRate,
            codec: self.codec
        )
    }

    private func applyResolutionPreset() {
        guard let size = self.selectedResolutionPreset.size() else {
            return
        }

        self.width = size.width
        self.height = size.height
    }
}

@MainActor
@Observable final class MovieExportCoordinator {
    var isPresented = false
    var phase: MovieExportSheetPhase = .settings
    var settingsViewModel: MovieExportSettingsViewModel?
    var completedFrames = 0
    var totalFrames = 0
    var destinationFilename = ""
    var errorMessage: String?

    @ObservationIgnored private var exportTask: Task<Void, Never>?

    var isExporting: Bool {
        self.phase == .exporting
    }

    var progressFraction: Double {
        guard self.totalFrames > 0 else {
            return 0
        }

        return Double(self.completedFrames) / Double(self.totalFrames)
    }

    func present(initialSettings: MovieExportSettings) {
        self.settingsViewModel = MovieExportSettingsViewModel(initialSettings: initialSettings)
        self.phase = .settings
        self.completedFrames = 0
        self.totalFrames = 0
        self.destinationFilename = ""
        self.errorMessage = nil
        self.exportTask = nil
        self.isPresented = true
    }

    func dismiss() {
        guard !self.isExporting else {
            return
        }

        self.settingsViewModel = nil
        self.phase = .settings
        self.completedFrames = 0
        self.totalFrames = 0
        self.destinationFilename = ""
        self.errorMessage = nil
        self.exportTask = nil
        self.isPresented = false
    }

    func beginExport(destinationURL: URL, totalFrames: Int, task: Task<Void, Never>) {
        self.destinationFilename = destinationURL.lastPathComponent
        self.completedFrames = 0
        self.totalFrames = totalFrames
        self.errorMessage = nil
        self.phase = .exporting
        self.exportTask = task
    }

    func updateProgress(completedFrames: Int, totalFrames: Int) {
        self.completedFrames = completedFrames
        self.totalFrames = totalFrames
    }

    func completeExport() {
        self.exportTask = nil
        self.phase = .settings
        self.completedFrames = 0
        self.totalFrames = 0
        self.destinationFilename = ""
        self.errorMessage = nil
        self.settingsViewModel = nil
        self.isPresented = false
    }

    func failExport(message: String?) {
        self.exportTask = nil
        self.phase = .settings
        self.completedFrames = 0
        self.totalFrames = 0
        self.destinationFilename = ""
        self.errorMessage = message
    }

    func cancelExport() {
        self.exportTask?.cancel()
    }
}

struct MovieExportSheetView: View {
    @Bindable var coordinator: MovieExportCoordinator

    let onDismiss: () -> Void
    let onContinue: (MovieExportConfiguration) -> Void

    var body: some View {
        Group {
            switch self.coordinator.phase {
            case .settings:
                if let settingsViewModel = self.coordinator.settingsViewModel {
                    MovieExportSettingsFormView(
                        viewModel: settingsViewModel,
                        errorMessage: self.coordinator.errorMessage,
                        onCancel: self.onDismiss,
                        onExport: {
                            self.coordinator.errorMessage = nil
                            self.onContinue(settingsViewModel.makeConfiguration())
                        }
                    )
                }
            case .exporting:
                MovieExportProgressView(
                    destinationFilename: self.coordinator.destinationFilename,
                    completedFrames: self.coordinator.completedFrames,
                    totalFrames: self.coordinator.totalFrames,
                    progressFraction: self.coordinator.progressFraction,
                    onCancel: self.coordinator.cancelExport
                )
            }
        }
        .interactiveDismissDisabled(self.coordinator.isExporting)
    }
}

struct MovieExportSettingsFormView: View {
    @Bindable var viewModel: MovieExportSettingsViewModel

    let errorMessage: String?
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Movie")
                .font(.title2)
                .padding()

            ScrollView {
                Form {
                    Section{
                        LabeledContent("Start Time") {
                            TextField(
                                "Start Time",
                                value: self.$viewModel.startTime,
                                format: .number.precision(.fractionLength(3))
                            )
                            .labelsHidden()
                        }
                        
                        LabeledContent("Duration") {
                            TextField(
                                "Duration",
                                value: self.$viewModel.duration,
                                format: .number.precision(.fractionLength(3))
                            )
                            .labelsHidden()
                        }
                    }
                    
                    Section {
                        LabeledContent("Resolution") {
                            Picker("Resolution", selection: self.$viewModel.selectedResolutionPreset) {
                                ForEach(self.viewModel.availableResolutionPresets) { preset in
                                    Text(preset.title()).tag(preset)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        LabeledContent("Width") {
                            TextField("Width", value: self.$viewModel.width, format: .number)
                                .labelsHidden()
                                .disabled(!self.viewModel.isUsingCustomResolution)
                        }

                        LabeledContent("Height") {
                            TextField("Height", value: self.$viewModel.height, format: .number)
                                .labelsHidden()
                                .disabled(!self.viewModel.isUsingCustomResolution)
                        }
                    }
                    
                    Section {
                        LabeledContent("Frame Rate") {
                            Picker("Frame Rate", selection: self.$viewModel.frameRatePreset) {
                                ForEach(MovieExportFrameRatePreset.allCases) { frameRatePreset in
                                    Text(frameRatePreset.label).tag(frameRatePreset)
                                }
                            }
                        }
                        .labelsHidden()
                    }

                    Section {
                        LabeledContent("Codec") {
                            Picker("Codec", selection: self.$viewModel.codec) {
                                ForEach(GraphMovieExportCodec.allCases) { codec in
                                    Text(codec.label).tag(codec)
                                }
                            }
                        }
                        .labelsHidden()
                    }
                }
                .formStyle(.grouped)
            }
            .scrollIndicators(.hidden)

            VStack(alignment: .leading) {
                if let validationMessage = self.viewModel.validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            HStack {
                Spacer()

                Button("Cancel", action: self.onCancel)

                Button("Continue", action: self.onExport)
                    .buttonStyle(.borderedProminent)
                    .disabled(!self.viewModel.canExport)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 500)
    }
}

struct MovieExportProgressView: View {
    let destinationFilename: String
    let completedFrames: Int
    let totalFrames: Int
    let progressFraction: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Exporting Movie")
                .font(.title2)

            Text(self.destinationFilename)
                .font(.headline)
                .textSelection(.enabled)

            ProgressView(value: self.progressFraction)
                .progressViewStyle(.linear)

            Text("\(self.completedFrames) of \(self.totalFrames) frames")
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("Cancel", action: self.onCancel)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 220)
    }
}
