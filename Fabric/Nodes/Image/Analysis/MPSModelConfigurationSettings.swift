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
                Picker(option.label, selection: option.selection)
                {
                    ForEach(option.choices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
            }
        }
        .padding()
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
