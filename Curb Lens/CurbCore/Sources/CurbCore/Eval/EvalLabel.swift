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
    /// Whether a photo may be tuned on.
    public enum Split: String, Codable, Sendable, CaseIterable {
        /// Used while improving the parser.
        case dev
        /// Held out: only scored at the end, never tuned on.
        case test
    }

    /// Photo path relative to the dataset folder.
    public var image: String
    /// dev or test.
    public var split: Split
    /// Tags such as "angle" or "dusk"; results are broken down by them.
    public var conditions: [String]
    /// What the sign says, panels separated by "|".
    public var transcript: String
    /// The rules a perfect reader would produce.
    public var rules: [ParkingRule]
    /// Times with the verdict a driver should get.
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
    /// The verdict category expected at `at`.
    public var expect: VerdictKind

    public init(at: String, expect: VerdictKind) {
        self.at = at
        self.expect = expect
    }

    /// A check time that isn't yyyy-MM-dd'T'HH:mm.
    public struct BadTime: Error, CustomStringConvertible {
        public var text: String
        public var description: String { "Bad check time \"\(text)\": expected yyyy-MM-dd'T'HH:mm" }
    }

    /// The check time as a Date in `calendar`'s time zone.
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
