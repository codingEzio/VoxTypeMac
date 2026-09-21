import CoreFoundation
import Foundation

enum TranscriptRefinement {
    struct Selection: Equatable {
        let text: String
        let status: String
    }

    static func select(
        apple: String,
        refined: String?,
        durationSeconds: TimeInterval? = nil,
        language: DictationLanguage = .englishUS,
        backend: RefinementBackend = .qwen3
    ) -> Selection {
        var apple = apple.trimmingCharacters(in: .whitespacesAndNewlines)
        var refined = refined?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if language == .traditionalChinese {
            apple = traditionalChinese(apple)
            refined = traditionalChinese(refined)
        }
        guard !refined.isEmpty,
            !shouldKeepApple(
                apple,
                over: refined,
                durationSeconds: durationSeconds,
                language: language
            )
        else {
            return Selection(text: apple, status: "apple-fallback")
        }

        if backend == .qwen3 {
            return Selection(text: refined, status: "qwen3-refined")
        }
        let merged = restoreLatinTokens(from: apple, in: refined)
        return Selection(
            text: merged,
            status: merged == refined ? "sensevoice-refined" : "sensevoice-merged"
        )
    }

    private static func shouldKeepApple(
        _ apple: String,
        over refined: String,
        durationSeconds: TimeInterval?,
        language: DictationLanguage
    ) -> Bool {
        guard !apple.isEmpty else { return false }
        if language == .englishUS, cjkCount(in: refined) > 0 {
            return true
        }
        if refined.count + 8 < apple.count / 2 { return true }

        let appleCJK = cjkCount(in: apple)
        let refinedCJK = cjkCount(in: refined)
        if appleCJK >= 6, refinedCJK * 3 < appleCJK { return true }

        let appleScript = dominantScript(in: apple)
        let refinedScript = dominantScript(in: refined)
        let flipped =
            appleScript != refinedScript
            && appleScript != .mixed && appleScript != .empty
            && refinedScript != .mixed && refinedScript != .empty
        guard flipped else { return false }
        return isBrief(apple) || isBrief(refined)
            || durationSeconds.map { $0 > 0 && $0 < 2.8 } == true
    }

    private static func restoreLatinTokens(from apple: String, in refined: String) -> String {
        var output = refined
        for token in latinTokens(in: apple) {
            if let existing = output.range(of: token, options: [.caseInsensitive, .literal]) {
                output.replaceSubrange(existing, with: token)
                continue
            }
            guard let tokenRange = apple.range(of: token, options: [.caseInsensitive, .literal]),
                let prefix = anchor(before: tokenRange.lowerBound, in: apple),
                let suffix = anchor(after: tokenRange.upperBound, in: apple)
            else { continue }
            if let hole = output.range(of: prefix + suffix) {
                output.replaceSubrange(hole, with: prefix + token + suffix)
                continue
            }
            replaceLatinSpan(between: prefix, and: suffix, in: &output, with: token)
        }
        return output
    }

    private static func replaceLatinSpan(
        between prefix: String,
        and suffix: String,
        in output: inout String,
        with token: String
    ) {
        guard let prefixRange = output.range(of: prefix),
            let suffixRange = output.range(
                of: suffix,
                range: prefixRange.upperBound..<output.endIndex
            )
        else { return }
        let candidateRange = prefixRange.upperBound..<suffixRange.lowerBound
        let candidate = output[candidateRange]
        guard candidate.count <= 32,
            candidate.unicodeScalars.contains(where: { $0.isASCII && Character($0).isLetter }),
            !candidate.contains(where: isCJK)
        else { return }

        let leading = candidate.prefix { $0.isWhitespace }
        let trailing = candidate.reversed().prefix {
            $0.isWhitespace || $0.isPunctuation
        }.reversed()
        output.replaceSubrange(candidateRange, with: leading + token + trailing)
    }

    private static func traditionalChinese(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        guard CFStringTransform(mutable, nil, "Simplified-Traditional" as CFString, false) else {
            return text
        }
        return String(mutable)
    }

    private static func latinTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var digits = false

        func flush() {
            if !token.isEmpty, digits || token.count >= 2 { tokens.append(token) }
            token = ""
        }

        for character in text {
            if character.isNumber || character == "." && digits && !token.contains(".") {
                if !token.isEmpty, !digits { flush() }
                digits = true
                token.append(character)
            } else if character.isLetter, character.isASCII {
                if !token.isEmpty, digits { flush() }
                digits = false
                token.append(character)
            } else {
                flush()
                digits = false
            }
        }
        flush()
        return tokens
    }

    private static func anchor(before index: String.Index, in text: String) -> String? {
        let prefix = text[..<index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = prefix.last else { return nil }
        return String(prefix.suffix(isCJK(last) ? 2 : 3))
    }

    private static func anchor(after index: String.Index, in text: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let suffix = text[index...].trimmingCharacters(in: separators)
        guard let first = suffix.first else { return nil }
        if isCJK(first) { return String(suffix.prefix(2)) }
        return latinTokens(in: String(suffix.prefix(24))).first ?? String(suffix.prefix(3))
    }

    private enum Script: Equatable { case latin, cjk, mixed, empty }

    private static func dominantScript(in text: String) -> Script {
        let latin = text.unicodeScalars.count { $0.isASCII && Character($0).isLetter }
        let cjk = cjkCount(in: text)
        if latin == 0, cjk == 0 { return .empty }
        if latin >= 2, cjk == 0 { return .latin }
        if cjk >= 1, latin == 0 { return .cjk }
        if latin >= 2, cjk >= 2 { return .mixed }
        return cjk > latin ? .cjk : .latin
    }

    private static func isBrief(_ text: String) -> Bool {
        let latinWords = latinTokens(in: text).count { $0.contains(where: \.isLetter) }
        return cjkCount(in: text) <= 8 && latinWords <= 6 && text.count <= 28
    }

    private static func cjkCount(in text: String) -> Int {
        text.unicodeScalars.count { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: true
            default: false
            }
        }
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: true
            default: false
            }
        }
    }
}
