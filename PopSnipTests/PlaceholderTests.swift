// MARK: - PlaceholderTests.swift
// `{{ }}` プレースホルダのパーサ・展開エンジン・カタログ（ローカライズキーの付け忘れ検知）を検証する。

import Foundation
import Testing
@testable import PopSnip

@Suite("PlaceholderParser の走査")
struct PlaceholderParserTests {
    @Test("単純なトークンを検出する")
    func detectsSimpleToken() {
        let occurrences = PlaceholderParser.scan("本日{{date}}時点で確認したところ")
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.keyword == "date")
        #expect(occurrences.first?.argument == nil)
        #expect(occurrences.first?.isEscaped == false)
    }

    @Test("引数付きトークンを検出する")
    func detectsTokenWithArgument() {
        let occurrences = PlaceholderParser.scan("{{date:yyyy-MM-dd}}")
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.keyword == "date")
        #expect(occurrences.first?.argument == "yyyy-MM-dd")
    }

    @Test("引数中のコロンは最初の1つだけで分割される（HH:mm のような書式を壊さない）")
    func splitsOnlyOnFirstColon() {
        let occurrences = PlaceholderParser.scan("{{time:HH:mm}}")
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.keyword == "time")
        #expect(occurrences.first?.argument == "HH:mm")
    }

    @Test("未知のキーワードも構文としては検出され、isKnown が false になる")
    func detectsUnknownKeywordAsUnknown() {
        let occurrences = PlaceholderParser.scan("{{dete}}")
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.keyword == "dete")
        #expect(occurrences.first?.isKnown == false)
    }

    @Test("閉じられていない \"{{\" はトークンとして検出しない")
    func ignoresUnterminatedOpenBraces() {
        let occurrences = PlaceholderParser.scan("abc {{date text")
        #expect(occurrences.isEmpty)
    }

    @Test("隣接した2連トークンをどちらも検出する")
    func detectsAdjacentTokens() {
        let occurrences = PlaceholderParser.scan("{{date}}{{time}}")
        #expect(occurrences.count == 2)
        #expect(occurrences.map(\.keyword) == ["date", "time"])
    }

    @Test("単一の波括弧や CSS 断片は誤検出しない")
    func ignoresSingleBraceFragments() {
        let occurrences = PlaceholderParser.scan(".foo { color: red; } { bar: baz }")
        #expect(occurrences.isEmpty)
    }

    @Test("バックスラッシュ前置でエスケープと判定される")
    func detectsEscapedToken() {
        let text = #"\{{date}} literal"#
        let occurrences = PlaceholderParser.scan(text)
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.isEscaped == true)
        #expect(occurrences.first?.keyword == "date")
    }
}

@Suite("PlaceholderExpander の展開")
struct PlaceholderExpanderTests {
    private let fixedContext = PlaceholderContext(
        now: Date(timeIntervalSince1970: 1_755_422_100), // 2025-08-17 09:15:00 UTC
        clipboardText: "クリップボードの中身",
        selectedText: "選択されていたテキスト",
        appName: "TextEdit",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(identifier: "UTC")!
    )

    @Test("日時系トークンが既定書式で展開される")
    func expandsDateTimeTokensWithDefaultFormat() {
        let expanded = PlaceholderExpander.expand("{{date}} {{time}} {{datetime}}", context: fixedContext)
        #expect(expanded.text == "2025/08/17 09:15 2025/08/17 09:15")
    }

    @Test("引数付き日付トークンは指定した書式で展開される")
    func expandsDateTokenWithCustomFormat() {
        let expanded = PlaceholderExpander.expand("{{date:yyyy-MM-dd}}", context: fixedContext)
        #expect(expanded.text == "2025-08-17")
    }

    @Test("年・月・日トークンが展開される")
    func expandsYearMonthDayTokens() {
        let expanded = PlaceholderExpander.expand("{{year}}/{{month}}/{{day}}", context: fixedContext)
        #expect(expanded.text == "2025/08/17")
    }

    @Test("クリップボード・選択範囲・アプリ名トークンが展開される")
    func expandsContextTokens() {
        let expanded = PlaceholderExpander.expand("[{{selection}}] {{clipboard}} @ {{app}}", context: fixedContext)
        #expect(expanded.text == "[選択されていたテキスト] クリップボードの中身 @ TextEdit")
    }

    @Test("UUID トークンは有効な UUID 文字列に展開される")
    func expandsUUIDToken() throws {
        let expanded = PlaceholderExpander.expand("{{uuid}}", context: fixedContext)
        #expect(UUID(uuidString: expanded.text) != nil)
    }

    @Test("未知のキーワードは展開せず原文のまま残る")
    func leavesUnknownKeywordUntouched() {
        let expanded = PlaceholderExpander.expand("本日{{dete}}確認", context: fixedContext)
        #expect(expanded.text == "本日{{dete}}確認")
        #expect(expanded.caretUTF16Offset == nil)
    }

    @Test("エスケープされたトークンは展開されず、バックスラッシュだけが除去される")
    func unescapesWithoutExpanding() {
        let expanded = PlaceholderExpander.expand(#"\{{date}} literal"#, context: fixedContext)
        #expect(expanded.text == "{{date}} literal")
    }

    @Test("{{cursor}} は表示テキストから除去され、キャレット位置が UTF-16 オフセットで返る")
    func cursorTokenIsRemovedAndReportsOffset() {
        let expanded = PlaceholderExpander.expand("本日{{cursor}}です", context: fixedContext)
        #expect(expanded.text == "本日です")
        #expect(expanded.caretUTF16Offset == "本日".utf16.count)
        #expect(expanded.caretCharacterOffsetFromEnd == "です".count)
    }

    @Test("{{cursor}} が複数ある場合、最初の1つだけがキャレット位置として採用され、残りは除去される")
    func onlyFirstCursorTokenIsConsumed() {
        let expanded = PlaceholderExpander.expand("{{cursor}}A{{cursor}}B", context: fixedContext)
        #expect(expanded.text == "AB")
        #expect(expanded.caretUTF16Offset == 0)
        #expect(expanded.caretCharacterOffsetFromEnd == "AB".count)
    }

    @Test(
        "絵文字（サロゲートペア）を含む本文では UTF-16 オフセットと書記素オフセットが異なる値になる"
    )
    func caretOffsetsDifferAcrossEncodingsWithEmoji() {
        let expanded = PlaceholderExpander.expand("🎉{{cursor}}end", context: fixedContext)
        #expect(expanded.text == "🎉end")
        // "🎉" は UTF-16 では2コードユニット（サロゲートペア）だが、書記素としては1文字。
        #expect(expanded.caretUTF16Offset == 2)
        #expect(expanded.caretCharacterOffsetFromEnd == "end".count)
    }

    @Test("プレースホルダを含まない本文はキャレット情報を持たずそのまま返る")
    func returnsPlainTextUnchangedWhenNoPlaceholders() {
        let expanded = PlaceholderExpander.expand("プレーンな本文", context: fixedContext)
        #expect(expanded.text == "プレーンな本文")
        #expect(expanded.caretUTF16Offset == nil)
        #expect(expanded.caretCharacterOffsetFromEnd == nil)
    }
}

@Suite("PlaceholderCatalog のローカライズキー整合性")
struct PlaceholderCatalogLocalizationTests {
    @Test("すべての定義の name/description キーが ja/en 両方の Localizable.strings に存在する")
    func allDefinitionKeysExistInBothLocalizations() throws {
        let repoRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PlaceholderTests.swift
            .deletingLastPathComponent() // PopSnipTests/
        let jaKeys = try loadStringsKeys(
            at: repoRootURL.appendingPathComponent("Sources/Resources/ja.lproj/Localizable.strings")
        )
        let enKeys = try loadStringsKeys(
            at: repoRootURL.appendingPathComponent("Sources/Resources/en.lproj/Localizable.strings")
        )

        for definition in PlaceholderCatalog.all {
            #expect(jaKeys.contains(definition.nameKey), "ja に \(definition.nameKey) が無い")
            #expect(jaKeys.contains(definition.descriptionKey), "ja に \(definition.descriptionKey) が無い")
            #expect(enKeys.contains(definition.nameKey), "en に \(definition.nameKey) が無い")
            #expect(enKeys.contains(definition.descriptionKey), "en に \(definition.descriptionKey) が無い")
        }
    }

    private func loadStringsKeys(at url: URL) throws -> Set<String> {
        let content = try String(contentsOf: url, encoding: .utf8)
        var keys: Set<String> = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\"") else {
                continue
            }
            let afterOpenQuote = line.dropFirst()
            guard let closingQuoteIndex = afterOpenQuote.firstIndex(of: "\"") else {
                continue
            }
            keys.insert(String(afterOpenQuote[afterOpenQuote.startIndex..<closingQuoteIndex]))
        }
        return keys
    }
}
