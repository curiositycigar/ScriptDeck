import Foundation

// Accepted only when decoding legacy library.json files.
enum ExecutionMode: String, Codable {
    case embedded, terminal
}
