import Foundation

/// One typed word of sign text.
public struct Token: Hashable, Sendable {
    /// What a word means to the parser.
    public enum Kind: Hashable, Sendable {
        /// Canonical sign keyword, e.g. "HOUR" for "HR".
        case keyword(String)
        /// A known word that doesn't change the rule ("VEHICLES WILL BE TOWED").
        case filler(String)
        /// "8AM", "12PM", "7:30AM"
        case time(TimeOfDay)
        case day(Weekday)
        /// "1ST" ... "31ST"
        case ordinal(Int)
        /// 1...12
        case month(Int)
        case number(Int)
        /// "&" or "AND"
        case and
        case dash
        case unknown(String)
    }

    /// The word's type and canonical value.
    public var kind: Kind
    /// The text as it appeared after normalization.
    public var text: String

    /// Separators carry no meaning alone; they don't count toward parse confidence.
    public var isSeparator: Bool { kind == .and || kind == .dash }
}

/// Splits normalized sign text into typed tokens.
public enum Tokenizer {
    /// Splits normalized text into typed tokens, e.g. "2 HOUR PARKING 8AM - 6PM" -> number, keyword, keyword, time, dash, time.
    public static func tokenize(_ text: String) -> [Token] {
        guard let re = try? NSRegularExpression(pattern: #"[A-Z0-9:]+|&|-"#) else { return [] }
        let upper = text.uppercased()
        let ns = upper as NSString
        return re.matches(in: upper, range: NSRange(location: 0, length: ns.length)).map {
            classify(ns.substring(with: $0.range))
        }
    }

    static func classify(_ word: String) -> Token {
        Token(kind: kind(of: word), text: word)
    }

    private static func kind(of word: String) -> Token.Kind {
        if word == "&" || word == "AND" { return .and }
        if word == "-" { return .dash }
        if let time = parseTime(word) { return .time(time) }
        if let ordinal = parseOrdinal(word) { return .ordinal(ordinal) }
        if word.allSatisfy(\.isNumber), let n = Int(word) { return .number(n) }
        if let day = Vocabulary.days[word] { return .day(day) }
        if let month = Vocabulary.months[word] { return .month(month) }
        if let keyword = Vocabulary.keywords[word] { return .keyword(keyword) }
        if Vocabulary.fillers.contains(word) { return .filler(word) }
        return .unknown(word)
    }

    /// "8AM" -> 08:00, "12PM" -> 12:00, "12AM" -> 00:00, "7:30PM" -> 19:30.
    static func parseTime(_ word: String) -> TimeOfDay? {
        guard let re = try? NSRegularExpression(pattern: #"^(\d{1,2})(?::(\d{2}))?(AM|PM)$"#),
              let m = re.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
              let hourRange = Range(m.range(at: 1), in: word),
              let meridiemRange = Range(m.range(at: 3), in: word),
              let hour = Int(word[hourRange]), (1...12).contains(hour) else {
            return nil
        }
        let minute = Range(m.range(at: 2), in: word).flatMap { Int(word[$0]) } ?? 0
        guard (0...59).contains(minute) else { return nil }
        let isPM = word[meridiemRange] == "PM"
        return TimeOfDay(hour: hour % 12 + (isPM ? 12 : 0), minute: minute)
    }

    /// "1ST" -> 1, "30TH" -> 30.
    static func parseOrdinal(_ word: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"^(\d{1,2})(ST|ND|RD|TH)$"#),
              let m = re.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
              let r = Range(m.range(at: 1), in: word),
              let n = Int(word[r]), n >= 1 else {
            return nil
        }
        return n
    }
}
