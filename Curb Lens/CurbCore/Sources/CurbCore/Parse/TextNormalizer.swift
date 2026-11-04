import Foundation

/// Normalized sign text plus a log of every change made to it.
public struct NormalizedText: Hashable, Sendable {
    public let text: String
    /// Each entry reads "before→after", e.g. "N0→NO" or "NOON→12PM".
    public let substitutions: [String]
}

/// Cleans raw OCR text into a predictable form for the tokenizer.
///
/// Example: "N0 PARKING 8 a.m.-l2 NOON" -> "NO PARKING 8AM - 12PM".
public enum TextNormalizer {
    public static func normalize(_ raw: String) -> NormalizedText {
        // "TOW ZONÉ" -> "TOW ZONE": fold accents OCR sometimes adds.
        let folded = raw.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var r = Rewriter(text: folded.uppercased())
        if folded != raw { r.note("accents removed") }

        // "PARK|NG", "|2" — a vertical bar is almost always an I or a 1.
        r.replace(#"\|"#, with: "I")
        // Unicode dashes and tildes -> ASCII hyphen.
        r.replace("[\u{2010}-\u{2015}\u{2212}~]", with: "-")
        // "OWNER'S" -> "OWNERS"; everything else that isn't sign text becomes a space.
        r.replace("['\u{2019}]", with: "", record: false)
        r.replace(#"[^A-Z0-9:&\-\s]"#, with: " ", record: false)

        // OCR character confusions, one token at a time.
        r.transformMatches(#"[A-Z0-9:]+"#, fixToken)

        // "l HR" / "I HR" -> "1 HR" (a lone I/L can't be fixed by the digit rule).
        r.replace(#"\b[IL](?=\s*(?:HR|HRS|HOUR|HOURS)\b)"#, with: "1")
        // "TOW LONE", "TOW 2ONE" — Z misread as L or 2 on real signs.
        r.replace(#"\bTOW\s+[L2]ONE\b"#, with: "TOW ZONE")
        // "TOW-AWAY ZONE" -> "TOW ZONE"
        r.replace(#"\bTOW\s*-?\s*AWAY\b"#, with: "TOW")
        // "ANYTIME" -> "ANY TIME"
        r.replace(#"\bANYTIME\b"#, with: "ANY TIME")
        // "8AM TO 6PM", "MON THRU SAT" -> ranges with a hyphen.
        r.replace(#"\b(?:TO|THRU|THROUGH|TIL|TILL|UNTIL)\b"#, with: "-")
        // "12 NOON", "NOON" -> "12PM"; "12 MIDNIGHT", "MIDNIGHT" -> "12AM".
        r.replace(#"\b(?:12\s*)?NOON\b"#, with: "12PM")
        r.replace(#"\b(?:12\s*)?MIDNIGHT\b"#, with: "12AM")
        // "8 A M", "8 AM" (and "8 A.M." after punctuation removal) -> "8AM".
        r.replace(#"(\d)\s*([AP])\s*M\b"#, with: "$1$2M")
        // "1201AM" -> "12:01AM", "730PM" -> "7:30PM" (OCR drops the colon).
        r.replace(#"\b(1[0-2]|0?[1-9])([0-5][0-9])(AM|PM)\b"#, with: "$1:$2$3")
        // Space out separators and collapse whitespace.
        r.replace(#"\s*([&-])\s*"#, with: " $1 ", record: false)
        r.replace(#"\s+"#, with: " ", record: false)

        return NormalizedText(text: r.text.trimmingCharacters(in: .whitespaces), substitutions: r.log)
    }

    // MARK: - Token-level OCR fixes

    private static let letterLookalikes: [Character: Character] = ["0": "O", "1": "I", "5": "S", "8": "B"]
    private static let digitLookalikes: [Character: Character] = ["O": "0", "I": "1", "L": "1", "S": "5", "B": "8"]

    /// "N0" -> "NO", "M0NDAY" -> "MONDAY" (only when the result is a sign word);
    /// "L2" -> "12", "1O:3OAM" -> "10:30AM" (only for tokens that are mostly digits).
    static func fixToken(_ token: String) -> String {
        let hasLetter = token.contains(where: \.isLetter)
        if hasLetter, token.contains(where: { letterLookalikes[$0] != nil }) {
            let candidate = String(token.map { letterLookalikes[$0] ?? $0 })
            if Vocabulary.all.contains(candidate) { return candidate }
        }
        return fixNumericToken(token)
    }

    /// Fixes letters inside time/number/ordinal tokens. Requires at least one real digit,
    /// so plain words like "IS" or "SOB" are never touched.
    private static func fixNumericToken(_ token: String) -> String {
        guard token.contains(where: \.isNumber) else { return token }
        let pattern = #"^([0-9OILSB]{1,2}(?::[0-9OILSB]{2})?)(AM|PM|ST|ND|RD|TH)?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              let coreRange = Range(match.range(at: 1), in: token) else {
            return token
        }
        let core = String(token[coreRange].map { digitLookalikes[$0] ?? $0 })
        let suffix = Range(match.range(at: 2), in: token).map { String(token[$0]) } ?? ""
        return core + suffix
    }
}

// MARK: - Regex helper

/// Applies regex rewrites to a string and records each change as "before→after".
struct Rewriter {
    private(set) var text: String
    private(set) var log: [String] = []

    init(text: String) {
        self.text = text
    }

    mutating func note(_ entry: String) {
        log.append(entry)
    }

    mutating func replace(_ pattern: String, with template: String, record: Bool = true) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        rewrite(re) { match, source in
            re.replacementString(for: match, in: source, offset: 0, template: template)
        } record: { record }
    }

    mutating func transformMatches(_ pattern: String, _ transform: (String) -> String) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        rewrite(re) { match, source in
            transform((source as NSString).substring(with: match.range))
        } record: { true }
    }

    private mutating func rewrite(_ re: NSRegularExpression,
                                  replacement: (NSTextCheckingResult, String) -> String,
                                  record: () -> Bool) {
        let source = text
        let ns = source as NSString
        let matches = re.matches(in: source, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return }
        let output = NSMutableString(string: source)
        var changes: [String] = []
        for match in matches.reversed() {
            let before = ns.substring(with: match.range)
            let after = replacement(match, source)
            guard before != after else { continue }
            output.replaceCharacters(in: match.range, with: after)
            if record() {
                changes.append("\(before.trimmingCharacters(in: .whitespaces))→\(after.trimmingCharacters(in: .whitespaces))")
            }
        }
        log.append(contentsOf: changes.reversed())
        text = output as String
    }
}
