import Foundation

func configurationError(_ error: Error) -> String {
    func location(_ path: [CodingKey]) -> String {
        path.reduce("$", { $0 + ($1.intValue.map { "[\($0)]" } ?? ".\($1.stringValue)") })
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context):
        return L("{0}.{1}: required field is missing.", "\(location(context.codingPath))", "\(key.stringValue)")
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
        return L("{0}: incorrect field type. {1}", "\(location(context.codingPath))", "\(context.debugDescription)")
    case DecodingError.dataCorrupted(let context):
        return "\(location(context.codingPath))：\(context.debugDescription)"
    default:
        let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
        return detail.map { "\(error.localizedDescription)\n\($0)" } ?? error.localizedDescription
    }
}
