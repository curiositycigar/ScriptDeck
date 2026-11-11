import Foundation

func runConfigurationValidationSelfTests() {
    var invalidArgument = ScriptParameter(id: "internal-invalid-argument", name: "Output folder",
                                          passing: .named, argumentName: "invalid name")
    var invalidSelection = ScriptParameter(id: "internal-invalid-selection", name: "Environment", kind: .select)
    invalidSelection.options = [ParameterOption(label: "Production", value: "production")]
    invalidSelection.defaultValue = "missing"
    var editable = invalidSelection
    editable.kind = .editableSelect
    editable.required = true
    let editableItem = ScriptItem(name: "Editable selection", path: "/bin/true", parameters: [editable])
    do {
        try LibraryDocument(scripts: [editableItem]).validate()
        let encoded = try JSONEncoder().encode(editable)
        let restored = try JSONDecoder().decode(ScriptParameter.self, from: encoded)
        check(restored == editable, "Editable selections preserve their kind, options, and custom default through JSON")
        for value in ["production", "custom environment; $(literal)", "Production"] {
            let arguments = try scriptArguments(for: editableItem, values: [editable.id: value])
            check(arguments == [value], "Editable selections pass preset values and literal custom text as one argument")
        }
        let defaultArguments = try scriptArguments(for: editableItem, values: [:])
        check(defaultArguments == ["missing"],
              "Editable selections accept custom defaults")
        check(parameterIssues(for: editableItem, values: [editable.id: ""])[editable.id] != nil,
              "Required editable selections still reject empty input")
        let strictItem = ScriptItem(path: "/bin/true", parameters: [invalidSelection])
        check(parameterIssues(for: strictItem, values: [invalidSelection.id: "custom"])[invalidSelection.id] != nil,
              "Existing selections continue to reject custom input")
    } catch { fatalError("Editable selection failed: \(error)") }
    var invalidEditable = editable
    invalidEditable.options = []
    var duplicate = invalidArgument
    duplicate.argumentName = "--output"
    let cases = [[invalidArgument], [invalidSelection], [invalidEditable], [duplicate, duplicate]]
    for parameters in cases {
        let item = ScriptItem(name: "Validation example", path: "/bin/true", parameters: parameters)
        do {
            try LibraryDocument(scripts: [item]).validate()
            fatalError("Invalid parameter configuration was accepted")
        } catch {
            check(error.localizedDescription.contains(parameters.last!.name) &&
                  !error.localizedDescription.contains(parameters.last!.id),
                  "Configuration validation identifies parameters by their display name rather than internal ID")
        }
    }
    invalidArgument.name = ""
    do {
        try LibraryDocument(scripts: [ScriptItem(path: "/bin/true", parameters: [invalidArgument])]).validate()
        fatalError("An unnamed parameter was accepted")
    } catch {
        check(error.localizedDescription.contains(L("Parameter {0}", "1")) &&
              !error.localizedDescription.contains(invalidArgument.id),
              "Unnamed parameters use their visible position instead of an internal ID")
    }
}
