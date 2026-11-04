import Foundation

/// What the parser understood from a sign, and how sure it is.
public struct ParseResult: Codable, Hashable, Sendable {
    public var rules: [ParkingRule]
    /// Words that weren't used by any rule. Non-empty means "double-check the sign".
    public var unparsedTokens: [String]
    /// Fraction of (non-separator) tokens used by a rule; 0 when no rule was found.
    public var confidence: Double
    /// OCR fixes and rewrites the normalizer made, e.g. "N0→NO".
    public var normalizations: [String]

    public init(rules: [ParkingRule], unparsedTokens: [String], confidence: Double, normalizations: [String]) {
        self.rules = rules
        self.unparsedTokens = unparsedTokens
        self.confidence = confidence
        self.normalizations = normalizations
    }
}

/// Turns sign text into `ParkingRule`s with a rule-based parser.
///
/// How it works:
/// 1. Every panel is normalized and tokenized; tokens from all panels form one stream, because OCR
///    often splits one sign panel over several lines ("NO PARKING" / "TOW ZONE" / "STREET CLEANING" / ...).
/// 2. "Heads" are found — the phrases that say what kind of rule this is (NO PARKING, 2 HOUR PARKING, ...).
/// 3. The stream is cut into segments, one per rule head. A generic NO PARKING merges with a following
///    STREET CLEANING / SNOW EMERGENCY / LOADING ZONE because together they describe a single rule.
/// 4. Each segment's modifiers (time ranges, days, ordinals, season, TOW ZONE, permit zone) are
///    collected; every token used is marked, and the rest are reported as unparsed.
public enum SignParser {
    public static func parse(panels: [String]) -> ParseResult {
        var tokens: [Token] = []
        var panelOf: [Int] = []
        var normalizations: [String] = []
        for (index, panel) in panels.enumerated() {
            let normalized = TextNormalizer.normalize(panel)
            normalizations += normalized.substitutions
            let panelTokens = Tokenizer.tokenize(normalized.text)
            tokens += panelTokens
            panelOf += Array(repeating: index, count: panelTokens.count)
        }

        var context = ParseContext(tokens: tokens, panelOf: panelOf)
        let heads = context.detectHeads()
        var rules: [ParkingRule] = []
        for segment in context.segments(for: heads) {
            rules += context.buildRules(for: segment)
        }

        let countable = tokens.indices.filter { !tokens[$0].isSeparator }
        let unparsed = countable.filter { !context.used[$0] }.map { tokens[$0].text }
        let confidence: Double
        if rules.isEmpty || countable.isEmpty {
            confidence = 0
        } else {
            confidence = Double(countable.count - unparsed.count) / Double(countable.count)
        }
        return ParseResult(rules: rules, unparsedTokens: unparsed,
                           confidence: confidence, normalizations: normalizations)
    }
}

// MARK: - Internals

/// The phrase that decides a rule's kind.
enum HeadKind: Equatable {
    case noParking, noStopping, streetCleaning, snowEmergency, loadingZone, permit
    case timeLimit(minutes: Int)
}

struct Head {
    var kind: HeadKind
    var range: Range<Int>
}

struct Segment {
    var head: HeadKind?
    var heads: [Head]
    var start: Int
    var end: Int
}

private enum Endpoint {
    case time(TimeOfDay)
    case bare(Int)       // "7" in "7-10AM"
}

struct ParseContext {
    let tokens: [Token]
    let panelOf: [Int]
    private(set) var used: [Bool]
    /// Current search bounds; accessors return nil outside them.
    private var lo = 0
    private var hi = 0

    init(tokens: [Token], panelOf: [Int]) {
        self.tokens = tokens
        self.panelOf = panelOf
        self.used = Array(repeating: false, count: tokens.count)
        self.hi = tokens.count
    }

    // MARK: Token accessors (bounded, skip used tokens)

    private func free(_ i: Int) -> Token.Kind? {
        (i >= lo && i < hi && !used[i]) ? tokens[i].kind : nil
    }

    private func kw(_ i: Int, _ words: String...) -> Bool {
        if case let .keyword(word)? = free(i) { return words.contains(word) }
        return false
    }

    private func number(_ i: Int) -> Int? {
        if case let .number(n)? = free(i) { return n }
        return nil
    }

    private func ordinal(_ i: Int) -> Int? {
        if case let .ordinal(n)? = free(i) { return n }
        return nil
    }

    private func weekOrdinal(_ i: Int) -> Int? {
        ordinal(i).flatMap { (1...5).contains($0) ? $0 : nil }
    }

    private func day(_ i: Int) -> Weekday? {
        if case let .day(d)? = free(i) { return d }
        return nil
    }

    private func month(_ i: Int) -> Int? {
        if case let .month(m)? = free(i) { return m }
        return nil
    }

    private func time(_ i: Int) -> TimeOfDay? {
        if case let .time(t)? = free(i) { return t }
        return nil
    }

    private func isDash(_ i: Int) -> Bool { free(i) == .dash }
    private func isAnd(_ i: Int) -> Bool { free(i) == .and }

    private mutating func mark(_ range: Range<Int>) {
        for i in range where i >= 0 && i < used.count { used[i] = true }
    }

    // MARK: Heads

    mutating func detectHeads() -> [Head] {
        lo = 0
        hi = tokens.count
        var heads: [Head] = []
        var i = 0
        while i < tokens.count {
            if let head = head(at: i) {
                heads.append(head)
                i = head.range.upperBound
            } else {
                i += 1
            }
        }
        return heads
    }

    private func head(at i: Int) -> Head? {
        // "NO PARKING"
        if kw(i, "NO"), kw(i + 1, "PARKING") { return Head(kind: .noParking, range: i..<i + 2) }
        // "NO STOPPING", "NO STANDING"
        if kw(i, "NO"), kw(i + 1, "STOPPING", "STANDING") { return Head(kind: .noStopping, range: i..<i + 2) }
        // "STREET CLEANING", "STREET SWEEPING" (or just "CLEANING" when OCR drops STREET)
        if kw(i, "STREET"), kw(i + 1, "CLEANING", "SWEEPING") {
            return Head(kind: .streetCleaning, range: i..<i + 2)
        }
        if kw(i, "CLEANING", "SWEEPING") { return Head(kind: .streetCleaning, range: i..<i + 1) }
        // "SNOW EMERGENCY"
        if kw(i, "SNOW"), kw(i + 1, "EMERGENCY") { return Head(kind: .snowEmergency, range: i..<i + 2) }
        // "LOADING ZONE", "LOADING"
        if kw(i, "LOADING") {
            return Head(kind: .loadingZone, range: i..<(kw(i + 1, "ZONE") ? i + 2 : i + 1))
        }
        // "RESIDENT PERMIT PARKING ONLY", "PERMIT PARKING ONLY", "RESIDENT PARKING"
        if kw(i, "RESIDENT", "PERMIT") {
            var j = i
            while kw(j, "RESIDENT", "PERMIT", "PARKING", "ONLY") { j += 1 }
            return Head(kind: .permit, range: i..<j)
        }
        // "2 HOUR PARKING", "1 HR PARKING", "15 MIN PARKING", "2 HOUR LIMIT"
        if let n = number(i), n > 0, kw(i + 1, "HOUR", "MIN") {
            let minutes = kw(i + 1, "HOUR") ? n * 60 : n
            var j = i + 2
            if kw(j, "PARKING") { j += 1 }
            if kw(j, "LIMIT") { j += 1 }
            return Head(kind: .timeLimit(minutes: minutes), range: i..<j)
        }
        return nil
    }

    // MARK: Segmentation

    func segments(for heads: [Head]) -> [Segment] {
        var segments = [Segment(head: nil, heads: [], start: 0, end: tokens.count)]
        for head in heads {
            let last = segments.count - 1
            if let merged = Self.merge(segments[last].head, head.kind) {
                segments[last].head = merged
                segments[last].heads.append(head)
                continue
            }
            // A new rule starts. If its panel has no earlier head, the whole panel belongs to it.
            let previousHeadEnd = segments[last].heads.last?.range.upperBound ?? segments[last].start
            let panelStart = tokens.indices.first { panelOf[$0] == panelOf[head.range.lowerBound] }
                ?? head.range.lowerBound
            let boundary = panelStart >= previousHeadEnd ? panelStart : head.range.lowerBound
            segments[last].end = boundary
            segments.append(Segment(head: head.kind, heads: [head], start: boundary, end: tokens.count))
        }
        return segments
    }

    /// Whether a new head continues the current rule. Returns the combined kind, or nil to start a new rule.
    static func merge(_ current: HeadKind?, _ new: HeadKind) -> HeadKind? {
        guard let current else { return new }
        switch (current, new) {
        // "NO PARKING / TOW ZONE / STREET CLEANING / ..." is one street-cleaning rule.
        case (.noParking, .streetCleaning), (.noParking, .snowEmergency), (.noParking, .loadingZone):
            return new
        // "SNOW EMERGENCY ROUTE / TOW ZONE / NO PARKING" is one snow-emergency rule.
        case (.snowEmergency, .noParking):
            return .snowEmergency
        default:
            return nil
        }
    }

    // MARK: Rule building

    mutating func buildRules(for segment: Segment) -> [ParkingRule] {
        guard let head = segment.head, segment.start < segment.end else { return [] }
        lo = segment.start
        hi = segment.end
        defer { lo = 0; hi = tokens.count }

        for h in segment.heads { mark(h.range) }

        let towZone = takeTowZone()
        takeAnyTime()
        let season = takeSeason()
        let windows = takeWindows()
        let nth = takeOrdinalWeekday()
        let except = takeExceptDays()
        let explicit = takeDayLists()
        takeKeyword("DAILY")
        let zone = head == .permit ? takePermitZone(after: segment.heads) : nil
        takeFillers()

        let days: DayRule
        if let nth {
            days = .nthWeekday(ordinals: nth.ordinals, weekday: nth.weekday)
        } else if explicit.isEmpty && except.isEmpty {
            days = .everyDay
        } else {
            let base = explicit.isEmpty ? Set(Weekday.allCases) : explicit
            let result = base.subtracting(except)
            days = result.count == Weekday.allCases.count ? .everyDay : .days(result)
        }

        let kind: RestrictionKind
        switch head {
        case .noParking: kind = .noParking
        case .noStopping: kind = .noStopping
        case .streetCleaning: kind = .streetCleaning
        case .snowEmergency: kind = .snowEmergency
        case .loadingZone: kind = .loadingZone
        case .permit: kind = .permitOnly(zone: zone)
        case let .timeLimit(minutes): kind = .timeLimit(minutes: minutes)
        }

        let source = tokens[segment.start..<segment.end].map(\.text).joined(separator: " ")
        let ruleWindows: [TimeWindow?] = windows.isEmpty ? [nil] : windows
        return ruleWindows.map {
            ParkingRule(kind: kind, days: days, window: $0, season: season, towZone: towZone, sourceText: source)
        }
    }

    // "TOW ZONE" anywhere in the segment.
    private mutating func takeTowZone() -> Bool {
        var found = false
        for i in lo..<hi where kw(i, "TOW") && kw(i + 1, "ZONE") {
            mark(i..<i + 2)
            found = true
        }
        return found
    }

    // "ANY TIME", "AT ALL TIMES" -> all day (the default), consumed so it counts as understood.
    private mutating func takeAnyTime() {
        for i in lo..<hi where kw(i, "ANY", "ALL") && kw(i + 1, "TIME") {
            mark(i..<i + 2)
        }
    }

    // "APR 1 - NOV 30", "APRIL 1ST - NOVEMBER 30TH", "DEC - MAR".
    private mutating func takeSeason() -> SeasonalRange? {
        for i in lo..<hi {
            guard let m1 = month(i) else { continue }
            if let d1 = dayOfMonth(i + 1), isDash(i + 2), let m2 = month(i + 3), let d2 = dayOfMonth(i + 4) {
                mark(i..<i + 5)
                return SeasonalRange(startMonth: m1, startDay: d1, endMonth: m2, endDay: d2)
            }
            if isDash(i + 1), let m2 = month(i + 2) {
                mark(i..<i + 3)
                return SeasonalRange(startMonth: m1, startDay: 1, endMonth: m2, endDay: Self.lastDay(ofMonth: m2))
            }
        }
        return nil
    }

    private func dayOfMonth(_ i: Int) -> Int? {
        let value = number(i) ?? ordinal(i)
        return value.flatMap { (1...31).contains($0) ? $0 : nil }
    }

    private static func lastDay(ofMonth month: Int) -> Int {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(0, min(11, month - 1))]
    }

    // "8AM - 12PM", "7:30AM - 9:30AM", "7 - 10AM", "8 - 6PM". Several windows give several rules.
    private mutating func takeWindows() -> [TimeWindow] {
        var windows: [TimeWindow] = []
        var i = lo
        while i < hi {
            if isDash(i + 1), let window = Self.window(from: endpoint(i), to: endpoint(i + 2)) {
                windows.append(window)
                mark(i..<i + 3)
                i += 3
            } else {
                i += 1
            }
        }
        return windows
    }

    private func endpoint(_ i: Int) -> Endpoint? {
        if let t = time(i) { return .time(t) }
        if let n = number(i), (1...12).contains(n) { return .bare(n) }
        return nil
    }

    private static func window(from a: Endpoint?, to b: Endpoint?) -> TimeWindow? {
        switch (a, b) {
        case let (.time(start)?, .time(end)?):
            return TimeWindow(start: start, end: end)
        case let (.bare(hour)?, .time(end)?):
            // Pick AM or PM so the window is as short as possible: "8-6PM" = 8AM-6PM, "10-12AM" = 10PM-12AM.
            let start = candidates(for: hour).min { duration($0, end) < duration($1, end) } ?? end
            return TimeWindow(start: start, end: end)
        case let (.time(start)?, .bare(hour)?):
            let end = candidates(for: hour).min { duration(start, $0) < duration(start, $1) } ?? start
            return TimeWindow(start: start, end: end)
        default:
            return nil
        }
    }

    private static func candidates(for hour: Int) -> [TimeOfDay] {
        [TimeOfDay(hour: hour % 12), TimeOfDay(hour: hour % 12 + 12)]
    }

    /// Minutes from a to b going forward; a zero-length window counts as a full day.
    private static func duration(_ a: TimeOfDay, _ b: TimeOfDay) -> Int {
        let d = (b.minutes - a.minutes + 1440) % 1440
        return d == 0 ? 1440 : d
    }

    // "2ND & 4TH TUESDAY", "1ST AND 3RD MON".
    private mutating func takeOrdinalWeekday() -> (ordinals: Set<Int>, weekday: Weekday)? {
        for i in lo..<hi {
            guard let first = weekOrdinal(i) else { continue }
            var ordinals: Set<Int> = [first]
            var j = i + 1
            while j < hi {
                if let next = weekOrdinal(j) {
                    ordinals.insert(next)
                    j += 1
                } else if isAnd(j) || isDash(j), let next = weekOrdinal(j + 1) {
                    ordinals.insert(next)
                    j += 2
                } else {
                    break
                }
            }
            if let weekday = day(j) {
                mark(i..<j + 1)
                return (ordinals, weekday)
            }
        }
        return nil
    }

    // "EXCEPT SUNDAY", "EXCEPT SAT & SUN". "EXCEPT HOLIDAYS" is left unparsed on purpose.
    private mutating func takeExceptDays() -> Set<Weekday> {
        var result: Set<Weekday> = []
        for i in lo..<hi where kw(i, "EXCEPT") {
            if let (days, end) = dayList(at: i + 1) {
                result.formUnion(days)
                mark(i..<end)
            }
        }
        return result
    }

    // "MON-FRI", "MON & WED", "MON WED FRI", "TUESDAY".
    private mutating func takeDayLists() -> Set<Weekday> {
        var result: Set<Weekday> = []
        var i = lo
        while i < hi {
            if let (days, end) = dayList(at: i) {
                result.formUnion(days)
                mark(i..<end)
                i = end
            } else {
                i += 1
            }
        }
        return result
    }

    private func dayList(at i: Int) -> (Set<Weekday>, Int)? {
        guard let first = day(i) else { return nil }
        var days: Set<Weekday> = [first]
        var last = first
        var j = i + 1
        while j < hi {
            if isDash(j), let next = day(j + 1) {
                days.formUnion(Self.dayRange(from: last, to: next))
                last = next
                j += 2
            } else if isAnd(j), let next = day(j + 1) {
                days.insert(next)
                last = next
                j += 2
            } else if let next = day(j) {
                days.insert(next)
                last = next
                j += 1
            } else {
                break
            }
        }
        return (days, j)
    }

    /// Inclusive, wrapping: SAT-MON = SAT, SUN, MON.
    private static func dayRange(from a: Weekday, to b: Weekday) -> Set<Weekday> {
        var days: Set<Weekday> = [a]
        var current = a
        while current != b {
            current = Weekday(rawValue: current.rawValue % 7 + 1) ?? b
            days.insert(current)
        }
        return days
    }

    private mutating func takeKeyword(_ word: String) {
        for i in lo..<hi where kw(i, word) { mark(i..<i + 1) }
    }

    // "RESIDENT PERMIT PARKING ONLY / BACK BAY" -> zone "BACK BAY".
    private mutating func takePermitZone(after heads: [Head]) -> String? {
        guard let permitHead = heads.first(where: { $0.kind == .permit }) else { return nil }
        var words: [String] = []
        var j = permitHead.range.upperBound
        while j < hi, let kind = free(j) {
            switch kind {
            case .unknown, .number, .keyword("ZONE"):
                words.append(tokens[j].text)
                j += 1
                continue
            default:
                break
            }
            break
        }
        guard !words.isEmpty else { return nil }
        mark(permitHead.range.upperBound..<j)
        return words.joined(separator: " ")
    }

    private mutating func takeFillers() {
        for i in lo..<hi {
            if case .filler? = free(i) { mark(i..<i + 1) }
        }
        takeKeyword("ONLY")
    }
}
