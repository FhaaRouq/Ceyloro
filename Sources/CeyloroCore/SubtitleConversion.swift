import Foundation

public enum SubtitleFormat: String, Codable, Sendable {
    case srt
    case vtt
}

public struct SubtitleCue: Equatable, Sendable {
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    public let text: String
    public let settings: String

    public init(startMilliseconds: Int, endMilliseconds: Int, text: String, settings: String = "") {
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.text = text
        self.settings = settings
    }
}

public enum SubtitleConversionError: Error, Equatable, Sendable {
    case emptyInput
    case invalidCue
    case invalidTimestamp
}

public struct SubtitleConversionPolicy: Sendable {
    public static let nativeTargets: [TargetFormat] = [.srt, .vtt, .txt]

    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        guard source.kind == .subtitle else { return [] }
        return Self.nativeTargets.filter { $0.fileExtension != source.fileExtension }
    }
}

public enum SubtitleTranscoder {
    public static func parse(_ text: String, format: SubtitleFormat) throws -> [SubtitleCue] {
        var lines = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        if format == .vtt {
            while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                lines.removeFirst()
            }
            guard let header = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  header == "WEBVTT" || header.hasPrefix("WEBVTT ") else {
                throw SubtitleConversionError.invalidCue
            }
            lines.removeFirst()
            while !lines.isEmpty, !lines[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.removeFirst()
            }
        }

        var cues: [SubtitleCue] = []
        var cursor = 0
        while cursor < lines.count {
            while cursor < lines.count && lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cursor += 1
            }
            guard cursor < lines.count else { break }

            if format == .vtt, ["NOTE", "STYLE", "REGION"].contains(where: { lines[cursor].hasPrefix($0) }) {
                repeat {
                    cursor += 1
                } while cursor < lines.count && !lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                continue
            }

            while cursor < lines.count, !lines[cursor].contains("-->") {
                cursor += 1
            }
            guard cursor < lines.count, lines[cursor].contains("-->") else {
                throw SubtitleConversionError.invalidCue
            }

            let timing = lines[cursor]
            cursor += 1
            let timingParts = timing.components(separatedBy: "-->")
            guard timingParts.count == 2 else { throw SubtitleConversionError.invalidCue }
            let start = try parseTimestamp(String(timingParts[0]).trimmingCharacters(in: .whitespaces))
            let right = String(timingParts[1]).trimmingCharacters(in: .whitespaces)
            let rightParts = right.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let endPart = rightParts.first else { throw SubtitleConversionError.invalidCue }
            let end = try parseTimestamp(String(endPart))
            let settings = rightParts.count > 1 ? String(rightParts[1]) : ""

            var textLines: [String] = []
            while cursor < lines.count, !lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textLines.append(lines[cursor])
                cursor += 1
            }
            guard !textLines.isEmpty, end >= start else { throw SubtitleConversionError.invalidCue }
            cues.append(SubtitleCue(startMilliseconds: start, endMilliseconds: end, text: textLines.joined(separator: "\n"), settings: settings))
        }

        guard !cues.isEmpty else { throw SubtitleConversionError.emptyInput }
        return cues
    }

    public static func convert(_ text: String, from source: SubtitleFormat, to target: SubtitleFormat) throws -> String {
        guard source != target else { return text }
        let cues = try parse(text, format: source)
        switch target {
        case .srt:
            return cues.enumerated().map { index, cue in
                "\(index + 1)\n\(timestamp(cue.startMilliseconds, separator: ",")) --> \(timestamp(cue.endMilliseconds, separator: ","))\n\(cue.text)"
            }.joined(separator: "\n\n") + "\n"
        case .vtt:
            let blocks = cues.map { cue in
                let suffix = cue.settings.isEmpty ? "" : " \(cue.settings)"
                return "\(timestamp(cue.startMilliseconds, separator: ".")) --> \(timestamp(cue.endMilliseconds, separator: "."))\(suffix)\n\(cue.text)"
            }
            return "WEBVTT\n\n" + blocks.joined(separator: "\n\n") + "\n"
        }
    }

    /// Extracts plain dialogue text from all cues, stripping timing headers and cue numbers.
    public static func extractDialogueText(_ text: String, from source: SubtitleFormat) throws -> String {
        let cues = try parse(text, format: source)
        return cues.map(\.text).joined(separator: "\n") + "\n"
    }

    private static func parseTimestamp(_ value: String) throws -> Int {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { throw SubtitleConversionError.invalidTimestamp }
        let hours: Int
        let minutes: Int
        let secondsPart: String
        if parts.count == 3 {
            guard let parsedHours = Int(parts[0]), let parsedMinutes = Int(parts[1]) else { throw SubtitleConversionError.invalidTimestamp }
            hours = parsedHours
            minutes = parsedMinutes
            secondsPart = String(parts[2])
        } else {
            guard let parsedMinutes = Int(parts[0]) else { throw SubtitleConversionError.invalidTimestamp }
            hours = 0
            minutes = parsedMinutes
            secondsPart = String(parts[1])
        }
        let secondsParts = secondsPart.split(separator: ".", omittingEmptySubsequences: false)
        guard secondsParts.count <= 2, let seconds = Int(secondsParts[0]), (0..<60).contains(minutes), (0..<60).contains(seconds) else {
            throw SubtitleConversionError.invalidTimestamp
        }
        let milliseconds: Int
        if secondsParts.count == 2 {
            let fraction = String(secondsParts[1])
            guard !fraction.isEmpty, fraction.allSatisfy({ $0.isNumber }), let raw = Int(fraction) else { throw SubtitleConversionError.invalidTimestamp }
            milliseconds = raw * Int(pow10(3 - min(fraction.count, 3)))
        } else {
            milliseconds = 0
        }
        guard hours >= 0, milliseconds < 1000 else { throw SubtitleConversionError.invalidTimestamp }
        return hours * 3_600_000 + minutes * 60_000 + seconds * 1_000 + milliseconds
    }

    private static func timestamp(_ milliseconds: Int, separator: Character) -> String {
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds / 60_000) % 60
        let seconds = (milliseconds / 1_000) % 60
        let remainder = milliseconds % 1_000
        let prefix = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        return prefix + String(separator) + String(format: "%03d", remainder)
    }

    private static func pow10(_ exponent: Int) -> Int {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(1) { value, _ in value * 10 }
    }
}
