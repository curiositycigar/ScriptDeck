import Foundation

func runConfigurationValidationSelfTests() {
    var invalidArgument = ScriptParameter(id: "internal-invalid-argument", name: "Output folder",
                                          passing: .named, argumentName: "invalid name")
    var invalidSelection = ScriptParameter(id: "internal-invalid-selection", name: "Environment", kind: .select)
    invalidSelection.options = [ParameterOption(label: "Production", value: "production")]
    invalidSelection.defaultValue = "missing"
    var duplicate = invalidArgument
    duplicate.argumentName = "--output"
    let cases = [[invalidArgument], [invalidSelection], [duplicate, duplicate]]
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
