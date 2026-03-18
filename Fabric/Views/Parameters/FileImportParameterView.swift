//
//  FileImportParameterView.swift
//  Fabric
//
//  Created by Anton Marini on 7/13/24.
//

import SwiftUI
import Satin
import UniformTypeIdentifiers

struct FileImportParameterView: View, Equatable
{
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<String>
    let allowedContentTypes: [UTType]

    @State private var isImporting: Bool = false
    @State private var isDropTargeted: Bool = false

    init(parameter: StringParameter, allowedContentTypes: [UTType] = [.data])
    {
        self.vm = ParameterObservableModel(label: parameter.label,
                                           get: { parameter.value },
                                           set: { parameter.value = $0 },
                                           publisher: parameter.valuePublisher )
        self.allowedContentTypes = allowedContentTypes
    }

    private var displayFilename: String {
        guard let urlString = vm.uiValue as String?,
              !urlString.isEmpty,
              let url = URL(string: urlString)
        else { return "No file selected" }
        return url.lastPathComponent
    }

    var body: some View
    {
        VStack(alignment: .leading, spacing: 4)
        {
            // Row 1: label (left) + filename (right)
            HStack
            {
                Text(self.vm.label)
                    .font(.system(size: CGFloat(ParameterConfig.labelFont), weight: .bold))
                    .lineLimit(1)

                Spacer()

                Text(displayFilename)
                    .font(.system(size: CGFloat(ParameterConfig.controlFont)))
                    .foregroundStyle(vm.uiValue.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Row 2: editable path (drop target) + browse button
            HStack(spacing: 6)
            {
                TextField("Drop file here\u{2026}", text: $vm.uiValue)
                    .font(.system(size: CGFloat(ParameterConfig.controlFont), design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else { return false }
                        vm.uiValue = url.standardizedFileURL.absoluteString
                        return true
                    } isTargeted: { targeted in
                        isDropTargeted = targeted
                    }

                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "folder")
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.borderless)
                .tint(.primary)
                .help("Browse\u{2026}")
            }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: self.allowedContentTypes,
                      allowsMultipleSelection: false,
                      onCompletion: { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    self.vm.uiValue = url.standardizedFileURL.absoluteString
                }
            case .failure(let error):
                print("FileImportParameterView: \(error)")
            }
        })
    }
}
