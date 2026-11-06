import Foundation

/// Incremental ANSI filtering; progress overwrites become chronological lines.
/// Works on bytes so split UTF-8 characters are preserved across writes.
struct PlainLogDecoder {
    private enum Mode { case text, escape, intermediate, csi, osc, string, stringEscape }
    private var mode: Mode = .text
    private var stringMode: Mode = .osc
    private var previousCR = false

    mutating func decode(_ data: Data) -> Data {
        var result = Data()
        for byte in data {
            switch mode {
            case .text:
                if byte == 0x1b { mode = .escape }
                else if byte == 13 { result.append(10); previousCR = true }
                else if byte == 10 {
                    if !previousCR { result.append(10) }
                    previousCR = false
                } else if byte == 9 || (byte >= 32 && byte != 127) {
                    result.append(byte)
                    previousCR = false
                }
            case .escape:
                switch byte {
                case 91: mode = .csi
                case 93: mode = .osc
                case 80, 88, 94, 95: mode = .string
                case 32...47: mode = .intermediate
                default: mode = .text
                }
            case .intermediate:
                if byte >= 48 && byte <= 126 { mode = .text }
            case .csi:
                if byte == 0x1b { mode = .escape }
                else if byte >= 64 && byte <= 126 { mode = .text }
            case .osc, .string:
                if byte == 7 && mode == .osc { mode = .text }
                else if byte == 0x1b { stringMode = mode; mode = .stringEscape }
            case .stringEscape:
                mode = byte == 92 ? .text : stringMode
            }
        }
        return result
    }
}
