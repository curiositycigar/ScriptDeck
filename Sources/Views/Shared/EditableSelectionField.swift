import SwiftUI

/// Keeps typed values literal while preset choices use their configured argument values.
struct EditableSelectionField: View {
    let parameter: ScriptParameter
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            TextField(parameter.placeholder.isEmpty ? L("Enter a parameter value") : parameter.placeholder,
                      text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(parameter.name)
            Menu {
                ForEach(parameter.options) { option in
                    Button { text = option.value } label: {
                        if text == option.value {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Choose an option"))
            .accessibilityLabel(L("Choose an option") + " · " + parameter.name)
        }
    }
}
