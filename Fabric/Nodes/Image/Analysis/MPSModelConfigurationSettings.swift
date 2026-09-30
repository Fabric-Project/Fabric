import SwiftUI

/// One menu row in a model node's Settings view. Model-shape and checkpoint
/// choices live here rather than on ports so graph data cannot trigger a
/// synchronous weight load or graph compilation during frame execution.
struct MPSModelConfigurationOption: Identifiable
{
    let id: String
    let label: String
    let choices: [String]
    let selection: Binding<String>

    init(label: String, choices: [String], selection: Binding<String>)
    {
        self.id = label
        self.label = label
        self.choices = choices
        self.selection = selection
    }
}

struct MPSModelConfigurationSettingsView: View
{
    let options: [MPSModelConfigurationOption]

    var body: some View
    {
        Form
        {
            ForEach(options) { option in
                MPSModelConfigurationPicker(option: option)
            }
        }
        .padding()
    }
}

/// One settings row. The node's settings are not observable, so a picker bound
/// straight to them would not redraw after a change; the row keeps the choice
/// in its own state, writes it through to the node, then re-reads the node so
/// a change the node rejected snaps back.
struct MPSModelConfigurationPicker: View
{
    let option: MPSModelConfigurationOption
    @State private var selection: String

    init(option: MPSModelConfigurationOption)
    {
        self.option = option
        self._selection = State(initialValue: option.selection.wrappedValue)
    }

    var body: some View
    {
        Picker(self.option.label, selection: self.$selection)
        {
            ForEach(self.option.choices, id: \.self) { choice in
                Text(choice).tag(choice)
            }
        }
        .onChange(of: self.selection) { _, newValue in
            self.option.selection.wrappedValue = newValue
            self.selection = self.option.selection.wrappedValue
        }
    }
}

enum LegacyModelConfigurationPort
{
    static func string(named name: String, from decoder: Decoder) -> String?
    {
        guard let container = try? decoder.container(keyedBy: Node.CodingKeys.self),
              let snapshots = try? container.decode([PortRegistry.Snapshot].self, forKey: .ports),
              let snapshot = snapshots.first(where: { $0.name == name })
        else
        {
            return nil
        }
        return (snapshot.payload.base as? NodePort<String>)?.value
    }
}
