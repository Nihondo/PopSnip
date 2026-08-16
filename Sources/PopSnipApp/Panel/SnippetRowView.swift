// MARK: - SnippetRowView.swift
// 検索結果 / 一覧の1行を表示する。ヒット箇所をハイライト表示する
// （PopSnip_UI_plan.md「検索結果は、タイトルと本文の一部を表示する（ヒット箇所をハイライト）」）。

import SwiftUI

/// 選択中の行のハイライト。`.regularMaterial`（半透明のビビッド背景）の上では
/// 低opacityの塗りだけだとブレンドでほぼ見えなくなるため、塗り + 縁取りの二重で強調する。
private extension View {
    func panelRowHighlight(isSelected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.32) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
        )
    }
}

/// スニペット1件の行。
struct SnippetRowView: View {
    let snippet: Snippet
    let tags: [SnippetTag]
    let titleHighlights: [HighlightRange]
    let bodyHighlights: [HighlightRange]
    let isTagColorShown: Bool
    let isSelected: Bool
    let indexHint: Int?
    let onToggleFavorite: () -> Void

    @Environment(\.appFontSize) private var appFontSize

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let indexHint, (1...9).contains(indexHint) {
                Text("\(indexHint)")
                    .font(appFontSize.font(DesignTokens.Typography.indexHint, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                highlightedText(
                    snippet.displayTitle,
                    ranges: titleHighlights,
                    baseFont: appFontSize.font(DesignTokens.Typography.rowTitle, weight: .medium)
                )
                .lineLimit(1)

                if bodyExcerpt.isEmpty == false {
                    highlightedText(
                        bodyExcerpt,
                        ranges: bodyHighlights,
                        baseFont: appFontSize.font(DesignTokens.Typography.rowBody)
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

            // お気に入りトグル。Button のタップ判定は行全体の .onTapGesture より優先されるため、
            // 星をクリックしても行の選択・挿入は発火しない。
            Button(action: onToggleFavorite) {
                Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(snippet.isFavorite ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .panelRowHighlight(isSelected: isSelected)
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

    @Environment(\.appFontSize) private var appFontSize

    var body: some View {
        HStack {
            TagChipView(tag: tag)
            Text("\(snippetCount)")
                .font(appFontSize.font(DesignTokens.Typography.rowBody))
                .foregroundStyle(.tertiary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .panelRowHighlight(isSelected: isSelected)
        .contentShape(Rectangle())
    }
}

/// タグドリルダウン中の「< タグ1 タグ2 ...」行（パンくず）。クリックだけでなく
/// カーソルキーでも選択できる（一覧の先頭項目として扱われる）。選択すると1段階だけ戻る。
/// パンくずの各タグチップは非クリック（表示のみ）で、行全体のクリック / Enter が
/// 「1段階戻る」の唯一の操作。
struct BackRowView: View {
    let tags: [SnippetTag]
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(tags) { tag in
                    TagChipView(tag: tag)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .panelRowHighlight(isSelected: isSelected)
        .contentShape(Rectangle())
    }
}
