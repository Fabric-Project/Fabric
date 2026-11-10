//
//  StreamKernelFieldsEditor.swift
//  Fabric
//

import SwiftUI

/// Lists a kernel's named streams, removes them, and adds one by name and element type.
struct StreamKernelFieldsEditor: View
{
    let title: String
    @Binding var fields: [StreamKernelField]
    @State private var newFieldName = ""
    @State private var newFieldTypeName = PortType.Vector3.rawValue

    var body: some View
    {
        VStack(alignment: .leading)
        {
            Text(title)
                .font(.headline)
            ForEach(fields, id: \.name)
            { field in
                StreamKernelFieldRow(field: field)
                {
                    fields.removeAll { $0.name == field.name }
                }
            }

            HStack
            {
                TextField("Name", text: $newFieldName)
                Picker("Type", selection: $newFieldTypeName)
                {
                    ForEach(PortType.streamElementTypes.map(\.rawValue), id: \.self) { typeName in
                        Text(typeName).tag(typeName)
                    }
                }
                .labelsHidden()
                Button("Add", systemImage: "plus")
                {
                    fields.append(StreamKernelField(name: newFieldName, elementType: PortType(rawValue: newFieldTypeName) ?? .Float))
                    newFieldName = ""
                }
                .disabled(newFieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct StreamKernelFieldRow: View
{
    let field: StreamKernelField
    let remove: () -> Void

    var body: some View
    {
        HStack
        {
            Text(field.name)
            Spacer()
            Text(field.elementTypeName)
                .foregroundStyle(.secondary)
            Button("Remove", systemImage: "minus", action: remove)
                .labelStyle(.iconOnly)
        }
    }
}

/// Picks where a kernel's count comes from: its Count input, or one of its stream inputs.
struct StreamKernelCountSourcePicker: View
{
    @Binding var countSource: String
    let inputs: [StreamKernelField]

    var body: some View
    {
        Picker("Count", selection: $countSource)
        {
            Text("Count Input").tag("")
            ForEach(inputs, id: \.name) { field in
                Text("Count of \(field.name)").tag(field.name)
            }
        }
    }
}
