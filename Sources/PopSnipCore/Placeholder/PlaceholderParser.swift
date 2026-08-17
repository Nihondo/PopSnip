// MARK: - PlaceholderParser.swift
// 本文中の `{{keyword}}` / `{{keyword:argument}}` を走査する。
// `PlaceholderExpander`（挿入時の値展開）と `SnippetBodyTextView`（編集中のシンタックス
// ハイライト）の両方がこの走査結果を共有することで、「展開されるトークン」と
// 「色付けされるトークン」がズレないようにする。

import Foundation

/// 本文中に見つかった1つの `{{ }}` トークン。
public struct PlaceholderOccurrence: Equatable, Sendable {
    /// `\{{...}}` エスケープの場合は先頭のバックスラッシュを含む全体範囲。
    public let range: Range<String.Index>
    public let keyword: String
    public let argument: String?
    /// 直前にバックスラッシュがあり、展開せずリテラル表示すべきトークンかどうか。
    public let isEscaped: Bool

    /// `PlaceholderCatalog` に登録済みのキーワードかどうか。
    public var isKnown: Bool {
        PlaceholderCatalog.definition(forKeyword: keyword) != nil
    }
}

/// `{{ }}` トークンのスキャナ。
/// `NSRegularExpression` は Swift 6 の厳格な並行性チェックで `Sendable` 化が煩雑なため、
/// `String.Index` ベースの手書きスキャナで実装する。
public enum PlaceholderParser {
    /// `text` 中の `{{ }}` トークンを開始位置順に走査する。
    public static func scan(_ text: String) -> [PlaceholderOccurrence] {
        var occurrences: [PlaceholderOccurrence] = []
        var searchStartIndex = text.startIndex

        while searchStartIndex < text.endIndex {
            guard let openRange = text.range(of: "{{", range: searchStartIndex..<text.endIndex) else {
                break
            }

            let isEscaped = openRange.lowerBound > text.startIndex
                && text[text.index(before: openRange.lowerBound)] == "\\"

            guard let closeRange = text.range(of: "}}", range: openRange.upperBound..<text.endIndex) else {
                // 対応する "}}" が以降に一切無い。これより後ろに有効なトークンは作れないため打ち切る。
                break
            }

            let innerContent = text[openRange.upperBound..<closeRange.lowerBound]

            // 改行や入れ子の "{{" を含む場合は、意図しない大きな範囲を1トークンとして
            // 飲み込んでしまう（例: 離れた場所にある2つの単一波括弧が偶然 "{{"/"}}"に見える）
            // ことを防ぐため、この "{{" は素通りして次の候補を探す。
            if innerContent.contains("{{") || innerContent.contains("\n") {
                searchStartIndex = text.index(after: openRange.lowerBound)
                continue
            }

            let keyword: String
            let argument: String?
            if let colonIndex = innerContent.firstIndex(of: ":") {
                keyword = String(innerContent[innerContent.startIndex..<colonIndex])
                argument = String(innerContent[innerContent.index(after: colonIndex)...])
            } else {
                keyword = String(innerContent)
                argument = nil
            }

            let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
            guard trimmedKeyword.isEmpty == false, trimmedKeyword.allSatisfy(\.isLetter) else {
                // `{{ "key": "value" }}` のような JSON 断片など、識別子の形をしていない中身は
                // プレースホルダとして扱わず素通りする。
                searchStartIndex = text.index(after: openRange.lowerBound)
                continue
            }

            let fullRange = isEscaped
                ? text.index(before: openRange.lowerBound)..<closeRange.upperBound
                : openRange.lowerBound..<closeRange.upperBound

            occurrences.append(
                PlaceholderOccurrence(
                    range: fullRange,
                    keyword: trimmedKeyword,
                    argument: argument,
                    isEscaped: isEscaped
                )
            )

            searchStartIndex = closeRange.upperBound
        }

        return occurrences
    }
}
