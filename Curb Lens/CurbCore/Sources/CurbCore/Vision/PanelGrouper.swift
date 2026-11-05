import CoreGraphics

/// One line of text found by OCR.
public struct RecognizedLine: Hashable, Sendable {
    /// The recognized text of the line.
    public var text: String
    /// Vision's confidence for the line, 0...1.
    public var confidence: Float
    /// Normalized, bottom-left origin, relative to the image OCR ran on.
    public var box: CGRect

    public init(text: String, confidence: Float, box: CGRect) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }
}

/// Groups OCR lines into sign panels.
///
/// 1. Lines on the same row (vertically overlapping) are joined left to right, because Vision
///    often returns "2" and "HOUR PARKING" as separate observations.
/// 2. Rows are read top to bottom; a new panel starts after a large vertical gap or when a row
///    begins with a panel keyword (NO, TOW, STREET, RESIDENT, LOADING, SNOW, "<n> HOUR").
public enum PanelGrouper {
    /// A gap bigger than this multiple of the median row height starts a new panel.
    public static let gapFactor: CGFloat = 1.2

    /// Groups OCR lines into sign panels, top to bottom: a new panel starts at a large vertical gap or a line beginning with a panel keyword (NO, TOW, STREET, RESIDENT, LOADING, SNOW, "<n> HOUR").
    public static func panels(from lines: [RecognizedLine]) -> [String] {
        let rows = self.rows(from: lines)
        guard !rows.isEmpty else { return [] }
        let heights = rows.map(\.box.height).sorted()
        let medianHeight = heights[heights.count / 2]

        var panels: [[String]] = []
        var previous: Row?
        for row in rows {
            let gap = previous.map { $0.box.minY - row.box.maxY } ?? 0
            let startsNew = previous == nil
                || gap > gapFactor * medianHeight
                || startsWithPanelKeyword(row.text)
            if startsNew {
                panels.append([row.text])
            } else {
                panels[panels.count - 1].append(row.text)
            }
            previous = row
        }
        return panels.map { $0.joined(separator: " ") }
    }

    struct Row {
        var text: String
        var box: CGRect
    }

    static func rows(from lines: [RecognizedLine]) -> [Row] {
        let sorted = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }          // top first (bottom-left origin)
        var groups: [[RecognizedLine]] = []
        for line in sorted {
            if let last = groups.last, let anchor = last.first, sameRow(anchor.box, line.box) {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            let ordered = group.sorted { $0.box.minX < $1.box.minX }
            let box = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            return Row(text: ordered.map(\.text).joined(separator: " "), box: box)
        }
    }

    /// Two boxes share a row when each one's vertical center lies inside the other's span.
    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        (a.minY...a.maxY).contains(b.midY) && (b.minY...b.maxY).contains(a.midY)
    }

    static func startsWithPanelKeyword(_ text: String) -> Bool {
        let tokens = Tokenizer.tokenize(TextNormalizer.normalize(text).text)
        guard let first = tokens.first else { return false }
        switch first.kind {
        case let .keyword(word):
            return ["NO", "TOW", "STREET", "RESIDENT", "LOADING", "SNOW"].contains(word)
        case .number:
            if tokens.count > 1, case let .keyword(next) = tokens[1].kind {
                return next == "HOUR" || next == "MIN"
            }
            return false
        default:
            return false
        }
    }
}
