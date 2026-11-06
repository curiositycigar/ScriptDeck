import Foundation

struct RunnerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
