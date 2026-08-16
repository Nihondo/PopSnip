// MARK: - SnippetPanelView.swift
// 検索パネルのメインコンテンツ。PopSnip_UI_plan.md のレイアウトに従う:
// 検索ボックス → (空欄時: タグ一覧 + 最近使用 / 入力時: 検索結果) → フッター。
//
// キー操作・選択状態は SnippetPanelViewModel に集約し、検索ボックスは IMESafeSearchField
// （プレーンな NSTextField ラッパー）を使う。SwiftUI の TextField + onKeyPress は
// 日本語入力の変換中に Enter / 矢印キーを誤って奪ってしまう既知の問題があるため採用していない。
// 実際のキー操作判定（矢印・Enter・Backspace・Esc・⌘1〜⌘9）は
// SnippetPanelPresenter 側の NSEvent ローカルモニタで一元的に行う
// （IME 変換中かどうかを hasMarkedText で判定できるのがそちら側のため）。
//
// セクションの描画は PanelPreferences.sectionOrder / enabledSections を ForEach で回す
// （[[docs-macos-snippet-menu-app-plan]] の設定駆動方針）。

import AppKit
import SwiftUI

private let panelCornerRadius: CGFloat = 16
private let panelWidth: CGFloat = 480

struct SnippetPanelView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var viewModel: SnippetPanelViewModel
    let onOpenEditor: () -> Void
    let onOpenList: () -> Void
    let onOpenSettings: () -> Void
    /// 生成された検索フィールドを Presenter へ引き渡す（キー操作は Presenter のキーモニタが担当する）。
    let onSearchFieldCreated: (NSTextField) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider().opacity(0.5)
            resultsList
            Divider().opacity(0.5)
            footer
        }
        .frame(width: panelWidth)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 10)
        .onAppear {
            store.reloadIfNeeded()
        }
        .onChange(of: viewModel.queryText) { _, _ in
            viewModel.resetHighlightForQueryChange()
        }
        .onChange(of: viewModel.selectedTagIDs) { _, _ in
            viewModel.resetHighlightForQueryChange()
        }
    }

    // MARK: - 検索ボックス

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            IMESafeSearchField(
                text: $viewModel.queryText,
                placeholder: L10n.string("panel.search.placeholder"),
                fontSize: 16,
                onFieldCreated: onSearchFieldCreated
            )
            .frame(height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 結果表示

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if viewModel.isSearching {
                    searchResultContent
                } else {
                    browsingContent
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 320)
    }

    /// 検索ボックスが空のとき: タグ一覧（ドリルダウン）+ 最近使用したスニペット。
    ///
    /// ドリルダウン中は listItems をそのまま enumerated() して描画する。
    /// 以前は「< タグ名」行と各スニペット行で別々にインデックスを計算していたため
    /// （viewModel.globalIndex(ofSnippetID:) と snippetsForSelectedTag(_:) を別々に呼ぶ構成）、
    /// 実際に選択されている項目と表示上のハイライト対象がズレる不具合があった。
    /// listItems の enumerated() を唯一の情報源にすることで、内容とインデックスが常に一致する。
    @ViewBuilder
    private var browsingContent: some View {
        if viewModel.isDrilledDown {
            ForEach(Array(viewModel.listItems.enumerated()), id: \.element.id) { index, item in
                row(for: item, at: index)
            }
        } else {
            ForEach(viewModel.preferences.orderedEnabledSections) { section in
                sectionView(for: section)
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: PanelSection) -> some View {
        switch section {
        case .tags:
            if store.library.tags.isEmpty == false {
                sectionHeader(L10n.string("panel.section.tags"))
                ForEach(store.library.tags) { tag in
                    TagRowView(
                        tag: tag,
                        snippetCount: viewModel.snippetCount(for: tag.id),
                        isSelected: viewModel.indexOfTagRow(tag.id) == viewModel.highlightedIndex
                    )
                    .onTapGesture { viewModel.drillIntoTag(tag.id) }
                }
            }
        case .recents:
            let recentSnippets = viewModel.recentSnippets()
            if recentSnippets.isEmpty == false {
                sectionHeader(L10n.string("panel.section.recents"))
                ForEach(recentSnippets) { snippet in
                    rowView(for: snippet, at: viewModel.globalIndex(ofSnippetID: snippet.id))
                }
            }
        case .allSnippets:
            EmptyView()
        case .favorites:
            EmptyView()
        }
    }

    private var searchResultContent: some View {
        ForEach(Array(viewModel.listItems.enumerated()), id: \.element.id) { index, item in
            row(for: item, at: index)
        }
    }

    /// `listItems` の1項目を、その場でのインデックス（キー操作の解決に使うのと同一の値）で描画する。
    @ViewBuilder
    private func row(for item: PanelListItem, at index: Int) -> some View {
        switch item {
        case .backToParent:
            BackRowView(tags: viewModel.selectedTags, isSelected: index == viewModel.highlightedIndex)
                .onTapGesture { viewModel.goBackOneLevel() }
        case .tag(let tag, let count):
            TagRowView(
                tag: tag,
                snippetCount: count,
                isSelected: index == viewModel.highlightedIndex
            )
            .onTapGesture { viewModel.drillIntoTag(tag.id) }
        case .snippet(let match):
            SnippetRowView(
                snippet: match.snippet,
                tags: viewModel.tags(for: match.snippet),
                titleHighlights: match.titleHighlights,
                bodyHighlights: match.bodyHighlights,
                isTagColorShown: viewModel.preferences.isTagColorShown,
                isSelected: index == viewModel.highlightedIndex,
                indexHint: viewModel.isSearching && viewModel.preferences.isNumberKeySelectionEnabled ? index + 1 : nil
            )
            .onTapGesture { viewModel.selectByIndex(index) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    // MARK: - フッター

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(titleKey: "panel.footer.register", systemImage: "plus", action: onOpenEditor)
            footerButton(titleKey: "panel.footer.list", systemImage: "list.bullet", action: onOpenList)
            Spacer()
            footerButton(titleKey: "panel.footer.settings", systemImage: "gearshape", action: onOpenSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func footerButton(titleKey: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.string(titleKey), systemImage: systemImage)
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private func rowView(for snippet: Snippet, at index: Int) -> some View {
        SnippetRowView(
            snippet: snippet,
            tags: viewModel.tags(for: snippet),
            titleHighlights: [],
            bodyHighlights: [],
            isTagColorShown: viewModel.preferences.isTagColorShown,
            isSelected: index == viewModel.highlightedIndex,
            indexHint: nil
        )
        .onTapGesture { viewModel.selectByIndex(index) }
    }
}
