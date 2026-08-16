// MARK: - SnippetPanelViewModel.swift
// 検索パネルの選択状態（検索語・タグドリルダウン・ハイライト行）とキー操作を集約する。
// IMESafeSearchField（doCommandBy 経由）と SnippetPanelPresenter（⌘1〜⌘9 の直接選択）の
// 両方から同じ経路でキー操作を発火できるよう、View から状態を切り出したもの。

import Foundation

/// 検索パネル内で選択可能な1項目。
enum PanelListItem: Identifiable {
    /// タグドリルダウン中の「< タグ名」行。クリックだけでなくカーソルキーでも選択できる。
    case backToParent
    case tag(SnippetTag, snippetCount: Int)
    case snippet(SnippetSearchMatch)

    var id: String {
        switch self {
        case .backToParent:
            return "back-to-parent"
        case .tag(let tag, _):
            return "tag-\(tag.id.uuidString)"
        case .snippet(let match):
            return "snippet-\(match.snippet.id.uuidString)"
        }
    }
}

@MainActor
final class SnippetPanelViewModel: ObservableObject {
    @Published var queryText = ""
    @Published var selectedTagID: UUID?
    @Published var highlightedIndex = 0

    let store: SnippetStore
    let preferences: PanelPreferences
    private let onSelectSnippet: (Snippet) -> Void
    private let onCancel: () -> Void

    init(
        store: SnippetStore,
        preferences: PanelPreferences,
        onSelectSnippet: @escaping (Snippet) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.onSelectSnippet = onSelectSnippet
        self.onCancel = onCancel
    }

    var isSearching: Bool {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var searchMatches: [SnippetSearchMatch] {
        SnippetSearchEngine.search(
            query: queryText,
            in: store.library.snippets,
            tags: store.library.tags,
            sortOrder: preferences.searchSortOrder,
            limit: preferences.searchResultLimit
        )
    }

    /// 現在表示されている項目一覧。キー操作のインデックス解決に使う。
    var listItems: [PanelListItem] {
        if isSearching {
            return searchMatches.map { .snippet($0) }
        }

        if let selectedTagID {
            var items: [PanelListItem] = [.backToParent]
            items.append(contentsOf: snippetsForSelectedTag(selectedTagID).map { .snippet(emptyMatch(for: $0)) })
            return items
        }

        var items: [PanelListItem] = []
        for section in preferences.orderedEnabledSections {
            switch section {
            case .tags:
                items.append(contentsOf: store.library.tags.map { .tag($0, snippetCount: snippetCount(for: $0.id)) })
            case .recents:
                items.append(contentsOf: recentSnippets().map { .snippet(emptyMatch(for: $0)) })
            case .allSnippets, .favorites:
                continue
            }
        }
        return items
    }

    // MARK: - キー操作

    /// PanelKeyBinding テーブルを経由してキー操作を解決する
    /// （[[docs-macos-snippet-menu-app-plan]] の設定駆動方針）。
    func handleKeyEvent(_ event: PanelKeyEvent) {
        guard let action = PanelKeyBinding.resolveAction(for: event, preferences: preferences) else {
            return
        }
        switch action {
        case .moveSelectionUp:
            moveSelectionUp()
        case .moveSelectionDown:
            moveSelectionDown()
        case .confirmSelection:
            confirmHighlighted()
        case .cancel:
            onCancel()
        case .selectByIndex(let index):
            selectByIndex(index)
        }
    }

    /// 検索ボックスが空の状態で Backspace が押された場合のみタグドリルダウンを解除する
    /// （PopSnip_UI_plan.md「タグドリルダウンは...Backspace で解除」）。
    /// - Returns: ドリルダウンを解除した場合は true（デフォルトの文字削除を抑止する）。
    func handleBackspaceForDrillDownIfNeeded() -> Bool {
        guard queryText.isEmpty, selectedTagID != nil else {
            return false
        }
        clearDrillDown()
        return true
    }

    func moveSelectionUp() {
        highlightedIndex = max(0, highlightedIndex - 1)
    }

    func moveSelectionDown() {
        highlightedIndex = min(max(0, listItems.count - 1), highlightedIndex + 1)
    }

    func confirmHighlighted() {
        guard listItems.indices.contains(highlightedIndex) else {
            return
        }
        confirm(listItems[highlightedIndex])
    }

    func selectByIndex(_ index: Int) {
        guard listItems.indices.contains(index) else {
            return
        }
        confirm(listItems[index])
    }

    func selectTag(_ tagID: UUID) {
        selectedTagID = tagID
        highlightedIndex = 0
    }

    func clearDrillDown() {
        selectedTagID = nil
        highlightedIndex = 0
    }

    func resetHighlightForQueryChange() {
        highlightedIndex = 0
    }

    private func confirm(_ item: PanelListItem) {
        switch item {
        case .backToParent:
            clearDrillDown()
        case .tag(let tag, _):
            selectTag(tag.id)
        case .snippet(let match):
            onSelectSnippet(match.snippet)
        }
    }

    // MARK: - データ解決

    func tags(for snippet: Snippet) -> [SnippetTag] {
        store.library.tags.filter { snippet.tagIDs.contains($0.id) }
    }

    func snippetsForSelectedTag(_ tagID: UUID) -> [Snippet] {
        store.library.snippets.filter { $0.tagIDs.contains(tagID) }
    }

    func snippetCount(for tagID: UUID) -> Int {
        store.library.snippets.filter { $0.tagIDs.contains(tagID) }.count
    }

    func recentSnippets() -> [Snippet] {
        Array(
            store.library.snippets
                .filter { $0.lastUsedAt != nil }
                .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
                .prefix(preferences.recentsLimit)
        )
    }

    func globalIndex(ofSnippetID id: UUID) -> Int {
        listItems.firstIndex { item in
            if case .snippet(let match) = item {
                return match.snippet.id == id
            }
            return false
        } ?? 0
    }

    func indexOfTagRow(_ tagID: UUID) -> Int {
        listItems.firstIndex { $0.id == "tag-\(tagID.uuidString)" } ?? 0
    }

    private func emptyMatch(for snippet: Snippet) -> SnippetSearchMatch {
        SnippetSearchMatch(snippet: snippet, score: 0, titleHighlights: [], bodyHighlights: [], tagHighlights: [:])
    }
}
