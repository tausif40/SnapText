import Foundation

/// Turns recognized fragments into plain text laid out the way it reads on screen.
nonisolated enum TextLayout {
    /// Fragments at most this long count as table cells rather than lines of running text.
    private static let longestCell = 24

    /// Joins `fragments`, which must be in Vision's reading order.
    ///
    /// Vision reads side-by-side text one column at a time. That suits columns of prose, but splits
    /// a table or a list of labels and values into all the labels followed by all the values, so
    /// those are put back together row by row.
    static func text(from fragments: [TextFragment], keepLineBreaks: Bool) -> String {
        let fragments = fragments.filter { !$0.text.allSatisfy(\.isWhitespace) }
        let rows = rows(of: fragments)
        let gap = keepLineBreaks ? "\t" : " "

        let lines: [String]
        if isTabular(rows) {
            lines = rows
                .sorted { $0[0].box.midY > $1[0].box.midY }
                .map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: gap) }
        } else {
            lines = linesInReadingOrder(fragments, gap: gap)
        }
        return lines.joined(separator: keepLineBreaks ? "\n" : " ")
    }

    /// One line per fragment, except that a line Vision split at a wide gap is put back together.
    private static func linesInReadingOrder(_ fragments: [TextFragment], gap: String) -> [String] {
        var lines: [String] = []
        for (index, fragment) in fragments.enumerated() {
            if index > 0, continues(fragments[index - 1].box, with: fragment.box) {
                lines[lines.count - 1] += gap + fragment.text
            } else {
                lines.append(fragment.text)
            }
        }
        return lines
    }

    /// Whether `next` carries on to the right of `box` on the same line.
    private static func continues(_ box: CGRect, with next: CGRect) -> Bool {
        sharesLine(box, next) && box.maxX <= next.minX
    }

    /// Groups fragments that sit on the same visual line.
    private static func rows(of fragments: [TextFragment]) -> [[TextFragment]] {
        var rows: [[TextFragment]] = []
        for fragment in fragments {
            if let index = rows.firstIndex(where: { sharesLine($0[0].box, fragment.box) }) {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows
    }

    /// Whether two boxes overlap vertically by at least half the height of the shorter one.
    private static func sharesLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap >= min(a.height, b.height) / 2
    }

    /// Whether side-by-side fragments are table cells: at least half of the lines holding several
    /// fragments must include a short one, such as a label or a number.
    private static func isTabular(_ rows: [[TextFragment]]) -> Bool {
        let shared = rows.filter { $0.count > 1 }
        let withCell = shared.filter { row in row.contains { $0.text.count <= longestCell } }
        return !shared.isEmpty && withCell.count * 2 >= shared.count
    }
}
