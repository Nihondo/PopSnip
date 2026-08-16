// MARK: - SnippetPanelView.swift
// 検索パネルのメインコンテンツ。PopSnip_UI_plan.md のレイアウトに従う:
// 検索ボックス → (空欄時: タグ一覧 + 最近使用 / 入力時: 検索結果) → フッター。
//
// セクションの描画は PanelPreferences.sectionOrder / enabledSections を ForEach で回し、
// キー操作は PanelKeyBinding テーブル経由で解決する
// （[[docs-macos-snippet-menu-app-plan]] の設定駆動方針）。

import SwiftUI

private let panelCornerRadius: CGFloat = 16
private let panelWidth: CGFloat = 480

/// 検索パネル内で選択可能な1項目。
private enum PanelListItem: Identifiable {
    case tag(SnippetTag, snippetCount: Int)
    case snippet(SnippetSearchMatch)

    var id: String {
        switch self {
        case .tag(let tag, _):
            return "tag-\(tag.id.uuidString)"
        case .snippet(let match):
            return "snippet-\(match.snippet.id.uuidString)"
        }
    }
}

struct SnippetPanelView: View {
    @ObservedObject var store: SnippetStore
    let preferences: PanelPreferences
    /// スニペットを選んだ時に呼ばれる。挿入処理・使用回数更新・パネルクローズは呼び出し側が担う。
    let onSelectSnippet: (Snippet) -> Void
    let onOpenEditor: () -> Void
    let onOpenList: () -> Void
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    @State private var queryText = ""
    @State private var selectedTagID: UUID?
    @State private var highlightedIndex = 0
    @FocusState private var isSearchFieldFocused: Bool

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
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                isSearchFieldFocused = true
            }
        }
        .onChange(of: queryText) { _, _ in
            highlightedIndex = 0
        }
        .onChange(of: selectedTagID) { _, _ in
            highlightedIndex = 0
        }
    }

    // MARK: - 検索ボックス

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.string("panel.search.placeholder"), text: $queryText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFieldFocused)
                .onKeyPress(.upArrow) { handle(.arrowUp) }
                .onKeyPress(.downArrow) { handle(.arrowDown) }
                .onKeyPress(.return) { handle(.confirm) }
                .onKeyPress(.delete) { handleBackspace() }
                .onKeyPress(characters: .init(charactersIn: "123456789")) { keyPress in
                    guard let digit = Int(keyPress.characters) else {
                        return .ignored
                    }
                    return handle(.digit(digit))
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 結果表示

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    browsingContent
                } else {
                    searchResultContent
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 320)
    }

    /// 検索ボックスが空のとき: タグ一覧（ドリルダウン）+ 最近使用したスニペット。
    @ViewBuilder
    private var browsingContent: some View {
        if let selectedTagID, let tag = store.library.tags.first(where: { $0.id == selectedTagID }) {
            drillDownHeader(tag: tag)
            ForEach(Array(snippetsForSelectedTag(tag.id).enumerated()), id: \.element.id) { index, snippet in
                rowView(for: snippet, at: index)
            }
        } else {
            ForEach(preferences.orderedEnabledSections) { section in
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
                ForEach(Array(store.library.tags.enumerated()), id: \.element.id) { index, tag in
                    let itemIndex = listItems.firstIndex { $0.id == "tag-\(tag.id.uuidString)" } ?? index
                    TagRowView(
                        tag: tag,
                        snippetCount: snippetCount(for: tag.id),
                        isSelected: itemIndex == highlightedIndex
                    )
                    .onTapGesture { selectedTagID = tag.id }
                }
            }
        case .recents:
            let recentSnippets = recentSnippets()
            if recentSnippets.isEmpty == false {
                sectionHeader(L10n.string("panel.section.recents"))
                ForEach(Array(recentSnippets.enumerated()), id: \.element.id) { _, snippet in
                    rowView(for: snippet, at: globalIndex(ofSnippetID: snippet.id))
                }
            }
        case .allSnippets:
            EmptyView()
        case .favorites:
            EmptyView()
        }
    }

    private var searchResultContent: some View {
        let matches = SnippetSearchEngine.search(
            query: queryText,
            in: store.library.snippets,
            tags: store.library.tags,
            sortOrder: preferences.searchSortOrder,
            limit: preferences.searchResultLimit
        )
        return ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
            SnippetRowView(
                snippet: match.snippet,
                tags: tags(for: match.snippet),
                titleHighlights: match.titleHighlights,
                bodyHighlights: match.bodyHighlights,
                isTagColorShown: preferences.isTagColorShown,
                isSelected: index == highlightedIndex,
                indexHint: preferences.isNumberKeySelectionEnabled ? index + 1 : nil
            )
            .onTapGesture { select(match.snippet) }
        }
    }

    private func drillDownHeader(tag: SnippetTag) -> some View {
        HStack(spacing: 6) {
            Button {
                selectedTagID = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            TagChipView(tag: tag)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
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

    // MARK: - キー操作

    private func handle(_ event: PanelKeyEvent) -> KeyPress.Result {
        guard let action = PanelKeyBinding.resolveAction(for: event, preferences: preferences) else {
            return .ignored
        }
        switch action {
        case .moveSelectionUp:
            highlightedIndex = max(0, highlightedIndex - 1)
        case .moveSelectionDown:
            highlightedIndex = min(listItems.count - 1, highlightedIndex + 1)
        case .confirmSelection:
            confirmHighlightedItem()
        case .cancel:
            onCancel()
        case .selectByIndex(let index):
            guard listItems.indices.contains(index) else {
                return .ignored
            }
            confirmItem(listItems[index])
        }
        return .handled
    }

    /// 検索ボックスが空の状態で Backspace が押された場合、タグのドリルダウンを解除する
    /// （PopSnip_UI_plan.md「タグドリルダウンは...Backspace で解除」）。
    /// 検索ボックスに文字が残っている場合は通常の文字削除に委ねる。
    private func handleBackspace() -> KeyPress.Result {
        guard queryText.isEmpty, selectedTagID != nil else {
            return .ignored
        }
        selectedTagID = nil
        return .handled
    }

    private func confirmHighlightedItem() {
        guard listItems.indices.contains(highlightedIndex) else {
            return
        }
        confirmItem(listItems[highlightedIndex])
    }

    private func confirmItem(_ item: PanelListItem) {
        switch item {
        case .tag(let tag, _):
            selectedTagID = tag.id
        case .snippet(let match):
            select(match.snippet)
        }
    }

    private func select(_ snippet: Snippet) {
        onSelectSnippet(snippet)
    }

    // MARK: - データ解決

    /// 現在表示されている項目一覧。キー操作のインデックス解決に使う。
    private var listItems: [PanelListItem] {
        if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let matches = SnippetSearchEngine.search(
                query: queryText,
                in: store.library.snippets,
                tags: store.library.tags,
                sortOrder: preferences.searchSortOrder,
                limit: preferences.searchResultLimit
            )
            return matches.map { .snippet($0) }
        }

        if let selectedTagID {
            return snippetsForSelectedTag(selectedTagID).map { snippet in
                .snippet(SnippetSearchMatch(snippet: snippet, score: 0, titleHighlights: [], bodyHighlights: [], tagHighlights: [:]))
            }
        }

        var items: [PanelListItem] = []
        for section in preferences.orderedEnabledSections {
            switch section {
            case .tags:
                items.append(contentsOf: store.library.tags.map { .tag($0, snippetCount: snippetCount(for: $0.id)) })
            case .recents:
                items.append(contentsOf: recentSnippets().map { snippet in
                    .snippet(SnippetSearchMatch(snippet: snippet, score: 0, titleHighlights: [], bodyHighlights: [], tagHighlights: [:]))
                })
            case .allSnippets, .favorites:
                continue
            }
        }
        return items
    }

    private func globalIndex(ofSnippetID id: UUID) -> Int {
        listItems.firstIndex { item in
            if case .snippet(let match) = item {
                return match.snippet.id == id
            }
            return false
        } ?? 0
    }

    private func rowView(for snippet: Snippet, at index: Int) -> some View {
        SnippetRowView(
            snippet: snippet,
            tags: tags(for: snippet),
            titleHighlights: [],
            bodyHighlights: [],
            isTagColorShown: preferences.isTagColorShown,
            isSelected: index == highlightedIndex,
            indexHint: nil
        )
        .onTapGesture { select(snippet) }
    }

    private func tags(for snippet: Snippet) -> [SnippetTag] {
        store.library.tags.filter { snippet.tagIDs.contains($0.id) }
    }

    private func snippetsForSelectedTag(_ tagID: UUID) -> [Snippet] {
        store.library.snippets.filter { $0.tagIDs.contains(tagID) }
    }

    private func snippetCount(for tagID: UUID) -> Int {
        store.library.snippets.filter { $0.tagIDs.contains(tagID) }.count
    }

    private func recentSnippets() -> [Snippet] {
        store.library.snippets
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(preferences.recentsLimit)
            .map { $0 }
    }
}
