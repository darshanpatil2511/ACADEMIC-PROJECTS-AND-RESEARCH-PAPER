import Foundation

// One entry of Dataset/labels.json (the ground truth for one photo):
//
//   {
//     "image": "images/IMG_0142.jpg",          // relative to the dataset folder
//     "split": "test",                          // "dev" (tune on it) or "test" (held out)
//     "conditions": ["angle", "dusk"],          // free-form tags; results are broken down by them
//     "transcript": "NO PARKING | TOW ZONE | STREET CLEANING | 2ND & 4TH TUESDAY | 8AM-12 NOON",
//     "rules": [ { ...ParkingRule JSON, same format as the app... } ],
//     "checks": [ { "at": "2026-11-10T09:00", "expect": "cannotPark" } ]
//   }

/// Ground truth for one dataset photo.
public struct EvalLabel: Codable, Hashable, Sendable {
    public enum Split: String, Codable, Sendable, CaseIterable {
        /// Used while improving the parser.
        case dev
        /// Held out: only scored at the end, never tuned on.
        case test
    }

    public var image: String
    public var split: Split
    public var conditions: [String]
    /// What the sign says, panels separated by "|".
    public var transcript: String
    public var rules: [ParkingRule]
    public var checks: [EvalCheck]

    public init(image: String, split: Split, conditions: [String], transcript: String, rules: [ParkingRule],
                checks: [EvalCheck]) {
        self.image = image
        self.split = split
        self.conditions = conditions
        self.transcript = transcript
        self.rules = rules
        self.checks = checks
    }

    private enum CodingKeys: String, CodingKey { case image, split, conditions, transcript, rules, checks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        image = try c.decode(String.self, forKey: .image)
        split = try c.decodeIfPresent(Split.self, forKey: .split) ?? .dev
        conditions = try c.decodeIfPresent([String].self, forKey: .conditions) ?? []
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        rules = try c.decodeIfPresent([ParkingRule].self, forKey: .rules) ?? []
        checks = try c.decodeIfPresent([EvalCheck].self, forKey: .checks) ?? []
    }

    /// Decodes the whole labels file (a JSON array).
    public static func decodeList(_ data: Data) throws -> [EvalLabel] {
        try JSONDecoder().decode([EvalLabel].self, from: data)
    }
}

/// "At this Boston time, the verdict should be X."
public struct EvalCheck: Codable, Hashable, Sendable {
    /// Boston wall-clock time, "yyyy-MM-dd'T'HH:mm".
    public var at: String
    public var expect: VerdictKind

    public init(at: String, expect: VerdictKind) {
        self.at = at
        self.expect = expect
    }

    public struct BadTime: Error, CustomStringConvertible {
        public var text: String
        public var description: String { "Bad check time \"\(text)\": expected yyyy-MM-dd'T'HH:mm" }
    }

    public func date(calendar: Calendar) throws -> Date {
        let parts = at.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard parts.count == 5,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                            hour: parts[3], minute: parts[4])) else {
            throw BadTime(text: at)
        }
        return date
    }
}

/// The verdict category a check expects.
public enum VerdictKind: String, Codable, Hashable, Sendable {
    case canPark, cannotPark, unreadable

    public init(_ verdict: Verdict) {
        switch verdict {
        case .canPark: self = .canPark
        case .cannotPark: self = .cannotPark
        case .unreadable: self = .unreadable
        }
    }
}
