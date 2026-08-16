// MARK: - SnippetPanelViewModel.swift
// 検索パネルの選択状態（検索語・タグドリルダウン・ハイライト行）とキー操作を集約する。
// IMESafeSearchField（doCommandBy 経由）と SnippetPanelPresenter（⌘1〜⌘9 の直接選択）の
// 両方から同じ経路でキー操作を発火できるよう、View から状態を切り出したもの。
//
// タグドリルダウンは複数段掘り下げられる（selectedTagIDs は選択順のパンくず）。
// AND 絞り込みされたスニペット群に含まれる「他のタグ」もサブ候補として提示することで、
// 複数タグを持つスニペットをタグを重ねて絞り込んでいける。
// ループ防止: サブ候補は「現在の絞り込み結果に含まれるタグ − 既に選択済みのタグ」として
// 計算するため、選択済みのタグは構造的に候補から除外され、同じタグを再選択できない。
// selectedTagIDs は選択のたびに末尾へ追加されるだけで単調増加し、上限はライブラリ内の
// 総タグ数という有限値のため、この操作列は必ず停止する。

import Foundation

/// 検索パネル内で選択可能な1項目。
enum PanelListItem: Identifiable {
    /// タグドリルダウン中の「< タグ名, タグ名, ...」行。クリックだけでなくカーソルキーでも選択できる。
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
    /// ドリルダウンのパンくず。選択順に末尾へ追加される。空ならトップレベル表示。
    @Published var selectedTagIDs: [UUID] = []
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

    var isDrilledDown: Bool {
        selectedTagIDs.isEmpty == false
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

    /// ドリルダウンのパンくず表示用。選択順を維持したまま `SnippetTag` を解決する。
    var selectedTags: [SnippetTag] {
        selectedTagIDs.compactMap { tagID in
            store.library.tags.first { $0.id == tagID }
        }
    }

    /// 現在表示されている項目一覧。キー操作のインデックス解決に使う。
    var listItems: [PanelListItem] {
        if isSearching {
            return searchMatches.map { .snippet($0) }
        }

        if isDrilledDown {
            let filteredSnippets = snippetsForSelectedTags(selectedTagIDs)
            var items: [PanelListItem] = [.backToParent]
            items.append(
                contentsOf: subTagCandidates(in: filteredSnippets, excluding: selectedTagIDs)
                    .map { .tag($0.tag, snippetCount: $0.count) }
            )
            items.append(contentsOf: filteredSnippets.map { .snippet(emptyMatch(for: $0)) })
            return items
        }

        var items: [PanelListItem] = []
        for section in preferences.orderedEnabledSections {
            switch section {
            case .tags:
                let globalCounts = Dictionary(
                    uniqueKeysWithValues: store.library.tags.map { ($0.id, snippetCount(for: $0.id)) }
                )
                items.append(
                    contentsOf: orderedTags(store.library.tags, counts: globalCounts)
                        .map { .tag($0, snippetCount: globalCounts[$0.id] ?? 0) }
                )
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

    /// 検索ボックスが空の状態で Backspace が押された場合、ドリルダウンを1段階だけ解除する
    /// （PopSnip_UI_plan.md「タグドリルダウンは...Backspace で解除」。複数段掘っている場合は
    /// 一気に最上位へ戻さず、直前の段階へ1つずつ戻す）。
    /// - Returns: 1段階戻した場合は true（デフォルトの文字削除を抑止する）。
    func handleBackspaceForDrillDownIfNeeded() -> Bool {
        guard queryText.isEmpty, isDrilledDown else {
            return false
        }
        goBackOneLevel()
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

    /// タグを1段階掘り下げる。トップレベルでの初回選択・ドリルダウン中のサブ候補選択の
    /// どちらもこの1つの関数で扱える（前者は空配列への追加として自然に扱われる）。
    /// 既に選択済みのタグは無視する（ループ防止・重複防止）。
    func drillIntoTag(_ tagID: UUID) {
        guard selectedTagIDs.contains(tagID) == false else {
            return
        }
        selectedTagIDs.append(tagID)
        highlightedIndex = 0
    }

    /// ドリルダウンを1段階だけ戻す。
    func goBackOneLevel() {
        guard selectedTagIDs.isEmpty == false else {
            return
        }
        selectedTagIDs.removeLast()
        highlightedIndex = 0
    }

    func resetHighlightForQueryChange() {
        highlightedIndex = 0
    }

    private func confirm(_ item: PanelListItem) {
        switch item {
        case .backToParent:
            goBackOneLevel()
        case .tag(let tag, _):
            drillIntoTag(tag.id)
        case .snippet(let match):
            onSelectSnippet(match.snippet)
        }
    }

    // MARK: - データ解決

    func tags(for snippet: Snippet) -> [SnippetTag] {
        store.library.tags.filter { snippet.tagIDs.contains($0.id) }
    }

    /// `tagIDs` すべてを持つスニペット（AND 絞り込み）。`tagIDs` が空なら空配列を返す。
    func snippetsForSelectedTags(_ tagIDs: [UUID]) -> [Snippet] {
        guard tagIDs.isEmpty == false else {
            return []
        }
        return store.library.snippets.filter { snippet in
            tagIDs.allSatisfy { snippet.tagIDs.contains($0) }
        }
    }

    /// `snippets` に含まれるタグを集計し、`excludedTagIDs` に含まれるものを除外して返す
    /// （ループ防止: 既に選択済みのタグを候補から構造的に取り除く）。
    /// カウントは `snippets` の中での一致件数。
    func subTagCandidates(
        in snippets: [Snippet],
        excluding excludedTagIDs: [UUID]
    ) -> [(tag: SnippetTag, count: Int)] {
        var countsByTagID: [UUID: Int] = [:]
        for snippet in snippets {
            for tagID in snippet.tagIDs where excludedTagIDs.contains(tagID) == false {
                countsByTagID[tagID, default: 0] += 1
            }
        }
        let candidateTags = store.library.tags.filter { countsByTagID[$0.id] != nil }
        return orderedTags(candidateTags, counts: countsByTagID).map { tag in
            (tag: tag, count: countsByTagID[tag.id] ?? 0)
        }
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

    /// `preferences.tagSortOrder` に従ってタグを並び替える。
    /// `.registrationOrder` は `tags` の受け取り順（= `store.library.tags` の順序）をそのまま維持し、
    /// `.snippetCountDescending` は `counts`（呼び出し元が渡す一致件数。トップレベルではライブラリ全体、
    /// サブ候補では現在の絞り込み結果内での件数）の多い順（同数は登録順を維持、`sorted` は安定ソート）。
    private func orderedTags(_ tags: [SnippetTag], counts: [UUID: Int]) -> [SnippetTag] {
        switch preferences.tagSortOrder {
        case .registrationOrder:
            return tags
        case .snippetCountDescending:
            return tags.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
        }
    }

    private func emptyMatch(for snippet: Snippet) -> SnippetSearchMatch {
        SnippetSearchMatch(snippet: snippet, score: 0, titleHighlights: [], bodyHighlights: [], tagHighlights: [:])
    }
}
