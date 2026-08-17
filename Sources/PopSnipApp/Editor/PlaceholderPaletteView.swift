// MARK: - PlaceholderPaletteView.swift
// プレースホルダの一覧を本文欄の直下にガイダンスとして表示する。
// 「プレースホルダは手入力ではなくガイダンスから貼り付けできるようにしたい」という要望に基づき、
// 各チップをクリックするとカーソル位置へ、ドラッグすると任意の位置へ挿入できるようにする。

import SwiftUI

struct PlaceholderPaletteView: View {
    var onInsert: (String) -> Void

    @AppStorage(UserDefaultsKeys.placeholderPaletteExpanded)
    private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                ForEach(PlaceholderCategory.allCases, id: \.self) { category in
                    let definitions = PlaceholderCatalog.all.filter { $0.category == category }
                    if definitions.isEmpty == false {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string(category.titleKey))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TagFlowLayout(spacing: 4, lineSpacing: 4) {
                                ForEach(definitions) { definition in
                                    PlaceholderChipView(definition: definition, onInsert: onInsert)
                                }
                            }
                        }
                    }
                }
                Text(L10n.string("placeholder.hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        } label: {
            Text(L10n.string("placeholder.section.title"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PlaceholderChipView: View {
    let definition: PlaceholderDefinition
    let onInsert: (String) -> Void

    var body: some View {
        Button {
            onInsert(definition.token)
        } label: {
            Text(definition.token)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(previewText)
        .onDrag {
            NSItemProvider(object: definition.token as NSString)
        }
    }

    /// ツールチップに表示する現在値のプレビュー。
    /// 日時系・UUID のように決定的に値が求まるものだけ実際の展開結果を見せ、
    /// クリップボード / 選択範囲 / アプリ名のように文脈依存のものは説明文にとどめる
    /// （編集画面で実クリップボード内容を覗き見せない、前面アプリ名が PopSnip 自身になって
    /// 紛らわしくなるのを避ける）。
    private var previewText: String {
        let name = L10n.string(definition.nameKey)
        let description = L10n.string(definition.descriptionKey)
        switch definition.kind {
        case .date, .time, .datetime, .year, .month, .day, .weekday, .uuid:
            let expanded = PlaceholderExpander.expand(definition.token, context: PlaceholderContext())
            return "\(name) — \(expanded.text)"
        case .clipboard, .selection, .app, .cursor:
            return "\(name) — \(description)"
        }
    }
}
