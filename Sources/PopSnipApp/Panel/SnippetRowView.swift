// MARK: - SnippetRowView.swift
// 検索結果 / 一覧の1行を表示する。ヒット箇所をハイライト表示する
// （PopSnip_UI_plan.md「検索結果は、タイトルと本文の一部を表示する（ヒット箇所をハイライト）」）。

import SwiftUI

/// スニペット1件の行。
struct SnippetRowView: View {
    let snippet: Snippet
    let tags: [SnippetTag]
    let titleHighlights: [HighlightRange]
    let bodyHighlights: [HighlightRange]
    let isTagColorShown: Bool
    let isSelected: Bool
    let indexHint: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let indexHint, (1...9).contains(indexHint) {
                Text("\(indexHint)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                highlightedText(
                    snippet.displayTitle,
                    ranges: titleHighlights,
                    baseFont: .system(size: 13, weight: .medium)
                )
                .lineLimit(1)

                if bodyExcerpt.isEmpty == false {
                    highlightedText(
                        bodyExcerpt,
                        ranges: bodyHighlights,
                        baseFont: .system(size: 11)
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if isTagColorShown, tags.isEmpty == false {
                    HStack(spacing: 4) {
                        ForEach(tags) { tag in
                            TagChipView(tag: tag)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    /// 本文の先頭行、または最初のヒット箇所を含む行を抜粋する。
    private var bodyExcerpt: String {
        let firstLine = snippet.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return String(firstLine)
    }

    /// `ranges` に該当する箇所を太字 + アクセントカラーでハイライトした `Text` を組み立てる。
    private func highlightedText(_ text: String, ranges: [HighlightRange], baseFont: Font) -> Text {
        guard ranges.isEmpty == false else {
            return Text(text).font(baseFont)
        }
        let nsText = text as NSString
        let sortedRanges = ranges.sorted { $0.location < $1.location }

        var result = Text("")
        var cursor = 0
        for range in sortedRanges {
            guard range.location >= cursor, range.location + range.length <= nsText.length else {
                continue
            }
            if range.location > cursor {
                let plainSegment = nsText.substring(with: NSRange(location: cursor, length: range.location - cursor))
                result = result + Text(plainSegment).font(baseFont)
            }
            let highlightedSegment = nsText.substring(with: range)
            result = result + Text(highlightedSegment).font(baseFont.bold()).foregroundColor(.accentColor)
            cursor = range.location + range.length
        }
        if cursor < nsText.length {
            let tailSegment = nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
            result = result + Text(tailSegment).font(baseFont)
        }
        return result
    }
}

/// タグ一覧の1行（階層ドリルダウン用）。
struct TagRowView: View {
    let tag: SnippetTag
    let snippetCount: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            TagChipView(tag: tag)
            Text("\(snippetCount)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
