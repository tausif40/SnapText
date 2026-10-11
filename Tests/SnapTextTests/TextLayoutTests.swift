import CoreGraphics
import Testing
@testable import SnapText

/// A fragment on a grid: `row` counts down from the top, `column` positions it left to right.
private func fragment(_ text: String, row: Int, column: Int = 0) -> TextFragment {
    let box = CGRect(x: 0.05 + 0.3 * Double(column), y: 0.9 - 0.1 * Double(row), width: 0.25, height: 0.06)
    return TextFragment(text: text, box: box)
}

@Suite struct TextLayoutTests {
    // Vision reports side-by-side text one column at a time; these fixtures follow that order.
    private let table = [
        fragment("Name", row: 0), fragment("report.pdf", row: 1), fragment("notes.txt", row: 2),
        fragment("Size", row: 0, column: 1), fragment("2.4 MB", row: 1, column: 1), fragment("812 bytes", row: 2, column: 1),
    ]
    private let proseColumns = [
        fragment("Left column starts here and wraps across", row: 0),
        fragment("several lines so that it reads as prose,", row: 1),
        fragment("then ends.", row: 2),
        fragment("Right column is separate text that should", row: 0, column: 2),
        fragment("come after the whole left column has been", row: 1, column: 2),
        fragment("read to the end.", row: 2, column: 2),
    ]

    @Test func singleColumnKeepsOneLinePerFragment() {
        let lines = [fragment("First line", row: 0), fragment("Second line", row: 1)]
        #expect(TextLayout.text(from: lines, keepLineBreaks: true) == "First line\nSecond line")
    }

    @Test func tableIsReadRowByRow() {
        #expect(TextLayout.text(from: table, keepLineBreaks: true) == "Name\tSize\nreport.pdf\t2.4 MB\nnotes.txt\t812 bytes")
    }

    @Test func columnsOfProseAreReadOneColumnAtATime() {
        let text = TextLayout.text(from: proseColumns, keepLineBreaks: true)
        #expect(text == proseColumns.map(\.text).joined(separator: "\n"))
    }

    @Test func lineSplitAtAWideGapIsPutBackTogether() {
        let line = [
            fragment("Ready, with three warnings in the last build", row: 0),
            fragment("Line 42, Column 7, Spaces: 4, UTF-8", row: 0, column: 2),
            fragment("A second line underneath the first one", row: 1),
        ]
        let expected = "Ready, with three warnings in the last build\tLine 42, Column 7, Spaces: 4, UTF-8\nA second line underneath the first one"
        #expect(TextLayout.text(from: line, keepLineBreaks: true) == expected)
    }

    @Test func withoutLineBreaksEverythingIsOneLine() {
        #expect(TextLayout.text(from: table, keepLineBreaks: false) == "Name Size report.pdf 2.4 MB notes.txt 812 bytes")
    }

    @Test func rowsAreOrderedFromTheTopEvenIfReportedOutOfOrder() {
        let shuffled = [table[2], table[5], table[0], table[3], table[1], table[4]]
        #expect(TextLayout.text(from: shuffled, keepLineBreaks: true) == "Name\tSize\nreport.pdf\t2.4 MB\nnotes.txt\t812 bytes")
    }

    @Test func blankFragmentsAreDropped() {
        let lines = [fragment("Text", row: 0), fragment("  ", row: 1), fragment("More", row: 2)]
        #expect(TextLayout.text(from: lines, keepLineBreaks: true) == "Text\nMore")
        #expect(TextLayout.text(from: [], keepLineBreaks: true) == "")
    }
}

@Suite struct PreferredLanguageTests {
    private let supported = ["en-US", "fr-FR", "pt-BR", "zh-Hans", "zh-Hant", "hi-IN"]

    @Test func matchesRegionalVariantsToTheSupportedLanguage() {
        #expect(TextRecognizer.preferredLanguages(among: supported, preferred: ["en-IN"]) == ["en-US"])
        #expect(TextRecognizer.preferredLanguages(among: supported, preferred: ["pt-PT", "hi-IN"]) == ["pt-BR", "hi-IN", "en-US"])
    }

    @Test func prefersTheMatchingScript() {
        #expect(TextRecognizer.preferredLanguages(among: supported, preferred: ["zh-Hant-TW"]) == ["zh-Hant", "en-US"])
    }

    @Test func skipsUnsupportedLanguagesButKeepsEnglish() {
        #expect(TextRecognizer.preferredLanguages(among: supported, preferred: ["sw-KE"]) == ["en-US"])
    }
}
