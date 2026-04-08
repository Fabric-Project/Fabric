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
    let viewerSize: (width: Int, height: Int)?
}

enum MovieExportResolutionPreset: String, CaseIterable, Identifiable {
    case currentViewer
    case hd720
    case hd1080
    case qhd1440
    case uhd4K
    case custom

    var id: String { self.rawValue }

    func title(viewerSize: (width: Int, height: Int)?) -> String {
        switch self {
        case .currentViewer:
            if let viewerSize {
                return "Current Viewer Size (\(viewerSize.width)×\(viewerSize.height))"
            }
            return "Current Viewer Size"
        case .hd720:
            return "1280×720"
        case .hd1080:
            return "1920×1080"
        case .qhd1440:
            return "2560×1440"
        case .uhd4K:
            return "3840×2160"
        case .custom:
            return "Custom"
        }
    }

    func size(viewerSize: (width: Int, height: Int)?) -> (width: Int, height: Int)? {
        switch self {
        case .currentViewer:
            return viewerSize
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

@MainActor
@Observable final class MovieExportSettingsViewModel {
    let viewerSize: (width: Int, height: Int)?
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
    var selectedFrameRatePreset: MovieExportFrameRatePreset {
        didSet {
            self.frameRate = self.selectedFrameRatePreset.frameRate
        }
    }
    var frameRate: Double
    var codec: GraphMovieExportCodec

    init(initialSettings: MovieExportSettings) {
        self.viewerSize = initialSettings.viewerSize
        self.availableResolutionPresets = initialSettings.viewerSize == nil
            ? [.hd720, .hd1080, .qhd1440, .uhd4K, .custom]
            : [.currentViewer, .hd720, .hd1080, .qhd1440, .uhd4K, .custom]
        self.startTime = initialSettings.startTime
        self.duration = initialSettings.duration
        self.selectedResolutionPreset = initialSettings.viewerSize == nil ? .hd1080 : .currentViewer
        self.width = initialSettings.viewerSize?.width ?? 1920
        self.height = initialSettings.viewerSize?.height ?? 1080
        self.selectedFrameRatePreset = .fps30
        self.frameRate = MovieExportFrameRatePreset.fps30.frameRate
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
        self.frameRate > 0
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

        if self.frameRate <= 0 {
            return "Frame rate must be greater than zero."
        }

        return nil
    }

    func makeConfiguration() -> MovieExportConfiguration {
        MovieExportConfiguration(
            startTime: self.startTime,
            duration: self.duration,
            size: (width: self.width, height: self.height),
            frameRate: self.frameRate,
            codec: self.codec
        )
    }

    private func applyResolutionPreset() {
        guard let size = self.selectedResolutionPreset.size(viewerSize: self.viewerSize) else {
            return
        }

        self.width = size.width
        self.height = size.height
    }
}

struct MovieExportSettingsView: View {
    @Bindable var viewModel: MovieExportSettingsViewModel

    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            ScrollView {
                Form {
                    LabeledContent("Start Time") {
                        TextField(
                            "Start Time",
                            value: self.$viewModel.startTime,
                            format: .number.precision(.fractionLength(3))
                        )
                        .frame(width: 120)
                    }

                    LabeledContent("Duration") {
                        TextField(
                            "Duration",
                            value: self.$viewModel.duration,
                            format: .number.precision(.fractionLength(3))
                        )
                        .frame(width: 120)
                    }

                    LabeledContent("Resolution") {
                        Picker("Resolution", selection: self.$viewModel.selectedResolutionPreset) {
                            ForEach(self.viewModel.availableResolutionPresets) { preset in
                                Text(preset.title(viewerSize: self.viewModel.viewerSize)).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    LabeledContent("Width") {
                        TextField("Width", value: self.$viewModel.width, format: .number)
                            .frame(width: 120)
                            .disabled(!self.viewModel.isUsingCustomResolution)
                    }

                    LabeledContent("Height") {
                        TextField("Height", value: self.$viewModel.height, format: .number)
                            .frame(width: 120)
                            .disabled(!self.viewModel.isUsingCustomResolution)
                    }

                    LabeledContent("Frame Rate") {
                        Picker("Frame Rate", selection: self.$viewModel.selectedFrameRatePreset) {
                            ForEach(MovieExportFrameRatePreset.allCases) { frameRatePreset in
                                Text(frameRatePreset.label).tag(frameRatePreset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    LabeledContent("Codec") {
                        Picker("Codec", selection: self.$viewModel.codec) {
                            Text(GraphMovieExportCodec.h264.label).tag(GraphMovieExportCodec.h264)
                            Text(GraphMovieExportCodec.hevc.label).tag(GraphMovieExportCodec.hevc)
                            Text(GraphMovieExportCodec.proRes422.label).tag(GraphMovieExportCodec.proRes422)
                            Text(GraphMovieExportCodec.proRes4444.label).tag(GraphMovieExportCodec.proRes4444)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                .formStyle(.grouped)
            }

            if let validationMessage = self.viewModel.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()

                Button("Cancel", action: self.onCancel)

                Button("Continue", action: self.onExport)
                    .buttonStyle(.borderedProminent)
                    .disabled(!self.viewModel.canExport)
            }
            .padding()
        }
        .frame(width: 460, height: 460)
    }
}
