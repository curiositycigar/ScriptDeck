import Foundation

enum ScriptClientVersion {
    static var current: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func requirement(at path: String) throws -> String? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let limit = 8192
        let bytes = try file.read(upToCount: limit + 1) ?? Data()
        let header = String(decoding: bytes.prefix(limit), as: UTF8.self)
        var lines = header.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if bytes.count > limit { lines.removeLast() }
        var requirement: String?
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "\u{FEFF}" })
            if line.isEmpty { continue }
            let comment: Substring
            if line.hasPrefix("#") { comment = line.dropFirst() }
            else if line.hasPrefix("//") { comment = line.dropFirst(2) }
            else { break }
            let metadata = comment.trimmingCharacters(in: .whitespaces)
            guard metadata.hasPrefix("scriptdeck:") else { continue }
            let fields = metadata.dropFirst("scriptdeck:".count).split(separator: "=", maxSplits: 1,
                                                                        omittingEmptySubsequences: false)
            guard fields.first?.trimmingCharacters(in: .whitespaces) == "version" else { continue }
            guard requirement == nil, fields.count == 2 else { throw invalidRequirement() }
            requirement = fields[1].trimmingCharacters(in: .whitespaces)
        }
        return requirement
    }

    static func check(_ requirement: String, current: String?) throws {
        let alternatives = try requirement.components(separatedBy: "||").map { alternative in
            let terms = alternative.split(whereSeparator: \.isWhitespace)
            guard !terms.isEmpty else { throw invalidRequirement() }
            return try terms.map(Constraint.init)
        }
        guard let current, let version = Version(current[...]) else {
            throw RunnerError(message: L("This script requires ScriptDeck {0}, but the current version could not be determined.", requirement))
        }
        guard alternatives.contains(where: { $0.allSatisfy { $0.matches(version) } }) else {
            throw RunnerError(message: L("This script requires ScriptDeck {0}. You are running {1}. Install a compatible version and try again.", requirement, current))
        }
    }

    private static func invalidRequirement() -> RunnerError {
        RunnerError(message: L("Invalid ScriptDeck version declaration in the script header."))
    }

    private struct Version: Comparable {
        let parts: [Int]

        init?(_ value: Substring) {
            let fields = value.split(separator: ".", omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            let numbers = fields.compactMap { field -> Int? in
                guard field.utf8.allSatisfy({ (48...57).contains($0) }),
                      field.count == 1 || field.first != "0" else { return nil }
                return Int(field)
            }
            guard numbers.count == 3 else { return nil }
            parts = numbers
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.parts.lexicographicallyPrecedes(rhs.parts)
        }
    }

    private struct Constraint {
        enum Operator: String, CaseIterable {
            case atLeast = ">=", atMost = "<=", above = ">", below = "<", equal = "=", caret = "^", tilde = "~"
        }

        let operation: Operator
        let bound: Version

        init(_ term: Substring) throws {
            let prefix = Operator.allCases.first { term.hasPrefix($0.rawValue) }
            operation = prefix ?? .equal
            guard let bound = Version(term.dropFirst(prefix?.rawValue.count ?? 0)) else {
                throw invalidRequirement()
            }
            self.bound = bound
        }

        func matches(_ version: Version) -> Bool {
            switch operation {
            case .atLeast: return version >= bound
            case .atMost: return version <= bound
            case .above: return version > bound
            case .below: return version < bound
            case .equal: return version == bound
            case .caret:
                let prefixLength = (bound.parts.firstIndex(where: { $0 != 0 }) ?? 2) + 1
                return version >= bound && version.parts.prefix(prefixLength) == bound.parts.prefix(prefixLength)
            case .tilde:
                return version >= bound && version.parts.prefix(2) == bound.parts.prefix(2)
            }
        }
    }
}
