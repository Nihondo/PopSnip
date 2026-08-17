// MARK: - SnippetPanelViewModel.swift
// 検索パネルの検索、タグ絞り込み、選択状態、キー操作を集約する。
// 選択は整数インデックスではなく、戻る行・タグ・スニペットの安定 ID で保持する。
// これにより、タグを1行に折りたたんだ表示でも、見た目と確定対象がずれない。

import Foundation

/// パネルに表示するタグ候補。件数は現在の検索スコープ内で算出する。
struct PanelTagCandidate: Identifiable, Equatable {
    let tag: SnippetTag
    let snippetCount: Int

    var id: UUID { tag.id }
}

/// 検索パネル内で選択可能な1項目。
enum PanelListItem: Identifiable {
    case backToParent
    case tag(PanelTagCandidate)
    /// `context` は同じスニペットが複数セクションに出る場合の識別子。
    case snippet(SnippetSearchMatch, context: String)

    var id: String {
        switch self {
        case .backToParent:
            return Self.backItemID
        case .tag(let candidate):
            return Self.tagItemID(candidate.tag.id)
        case .snippet(let match, let context):
            return Self.snippetItemID(match.snippet.id, context: context)
        }
    }

    static let backItemID = "back-to-parent"
    static let tagStripItemID = "tag-strip"

    static func tagItemID(_ tagID: UUID) -> String {
        "tag-\(tagID.uuidString)"
    }

    static func snippetItemID(_ snippetID: UUID, context: String) -> String {
        "snippet-\(context)-\(snippetID.uuidString)"
    }
}

/// 行の増減やタグ表示形式に影響されない、パネル内の安定した選択状態。
enum PanelSelection: Equatable {
    case backToParent
    case tag(UUID)
    case snippet(UUID, context: String)
}

@MainActor
final class SnippetPanelViewModel: ObservableObject {
    @Published var queryText = ""
    /// ドリルダウンのパンくず。選択順に末尾へ追加する。
    @Published var selectedTagIDs: [UUID] = []
    @Published private(set) var selection: PanelSelection?

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
        resetSelectionForContentChange()
    }

    var isSearching: Bool {
        trimmedQuery.isEmpty == false
    }

    var isDrilledDown: Bool {
        selectedTagIDs.isEmpty == false
    }

    /// 選択済みタグがある場合は、その AND 絞り込み内だけを検索対象にする。
    var scopedSnippets: [Snippet] {
        isDrilledDown ? snippetsForSelectedTags(selectedTagIDs) : store.library.snippets
    }

    var searchMatches: [SnippetSearchMatch] {
        SnippetSearchEngine.search(
            query: queryText,
            in: scopedSnippets,
            tags: store.library.tags,
            sortOrder: preferences.searchSortOrder,
            limit: preferences.searchResultLimit
        )
    }

    /// タグセクションが有効なときだけ、現在のスコープと検索語に合う候補を返す。
    var visibleTagCandidates: [PanelTagCandidate] {
        guard preferences.enabledSections.contains(.tags) else {
            return []
        }
        let candidates = isDrilledDown ? scopedTagCandidates() : globalTagCandidates()
        guard isSearching else {
            return candidates
        }
        return candidates.filter {
            $0.tag.name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// ドリルダウンのパンくず表示用。選択順を維持する。
    var selectedTags: [SnippetTag] {
        selectedTagIDs.compactMap { tagID in
            store.library.tags.first { $0.id == tagID }
        }
    }

    /// 表示内容とキー操作が参照する唯一の論理項目列。
    var listItems: [PanelListItem] {
        if isSearching || isDrilledDown {
            return scopedListItems()
        }
        return topLevelListItems()
    }

    /// 検索中またはドリルダウン中に表示するスニペット項目。
    var scopedSnippetItems: [PanelListItem] {
        let context = isSearching ? "search" : "drilldown"
        let matches = isSearching ? searchMatches : scopedSnippets.map(emptyMatch(for:))
        return matches.map { .snippet($0, context: context) }
    }

    var highlightedTagID: UUID? {
        guard case .tag(let tagID) = selection else {
            return nil
        }
        return tagID
    }

    /// 縦スクロール側の追従先。1行表示のタグはストリップ全体を指す。
    var highlightedItemID: String? {
        switch selection {
        case .backToParent:
            return PanelListItem.backItemID
        case .tag(let tagID):
            return preferences.tagLayoutStyle == .horizontalStrip
                ? PanelListItem.tagStripItemID
                : PanelListItem.tagItemID(tagID)
        case .snippet(let snippetID, let context):
            return PanelListItem.snippetItemID(snippetID, context: context)
        case nil:
            return nil
        }
    }

    // MARK: - キー操作

    /// PanelKeyBinding を経由してキーを処理する。処理したとき true を返す。
    @discardableResult
    func handleKeyEvent(_ event: PanelKeyEvent) -> Bool {
        guard let action = PanelKeyBinding.resolveAction(for: event, preferences: preferences) else {
            return false
        }
        switch action {
        case .moveSelectionUp:
            return moveVerticalSelection(by: -1)
        case .moveSelectionDown:
            return moveVerticalSelection(by: 1)
        case .moveTagSelectionPrevious:
            return moveTagSelection(by: -1)
        case .moveTagSelectionNext:
            return moveTagSelection(by: 1)
        case .confirmSelection:
            return confirmSelection()
        case .cancel:
            onCancel()
            return true
        case .selectByIndex(let index):
            return selectSnippetByOrdinal(index)
        }
    }

    /// 検索ボックスが空の状態で Backspace が押されたら、1段階戻る。
    func handleBackspaceForDrillDownIfNeeded() -> Bool {
        guard queryText.isEmpty, isDrilledDown else {
            return false
        }
        goBackOneLevel()
        return true
    }

    /// タグ表示中のみ、Tab / Shift+Tab / 左右キーで候補を循環する。
    func moveTagSelection(by offset: Int) -> Bool {
        guard case .tag(let tagID) = selection, visibleTagCandidates.isEmpty == false else {
            return false
        }
        let ids = visibleTagCandidates.map(\.id)
        guard let currentIndex = ids.firstIndex(of: tagID) else {
            selection = .tag(ids[0])
            return true
        }
        let nextIndex = (currentIndex + offset + ids.count) % ids.count
        selection = .tag(ids[nextIndex])
        return true
    }

    func confirmSelection() -> Bool {
        guard let selection, let item = item(matching: selection) else {
            return false
        }
        confirm(item)
        return true
    }

    /// 検索中のタグ候補を選ぶと検索語を消し、絞り込み条件に追加する。
    func drillIntoTag(_ tagID: UUID) {
        guard selectedTagIDs.contains(tagID) == false else {
            return
        }
        queryText = ""
        selectedTagIDs.append(tagID)
        selection = .backToParent
    }

    /// ドリルダウンを1段階だけ戻す。
    func goBackOneLevel() {
        guard selectedTagIDs.isEmpty == false else {
            return
        }
        selectedTagIDs.removeLast()
        resetSelectionForContentChange()
    }

    /// 検索語や絞り込み条件が変わったとき、先頭の表示項目へ安全に戻す。
    func resetSelectionForContentChange() {
        selection = listItems.first.map(selection(for:))
    }

    func isTagSelected(_ tagID: UUID) -> Bool {
        selection == .tag(tagID)
    }

    func isBackSelected() -> Bool {
        selection == .backToParent
    }

    func isSnippetSelected(_ snippetID: UUID, context: String) -> Bool {
        selection == .snippet(snippetID, context: context)
    }

    func selectSnippet(_ snippet: Snippet) {
        onSelectSnippet(snippet)
    }

    // MARK: - データ解決

    func tags(for snippet: Snippet) -> [SnippetTag] {
        store.library.tags.filter { snippet.tagIDs.contains($0.id) }
    }

    /// `tagIDs` すべてを持つスニペット（AND 絞り込み）。
    func snippetsForSelectedTags(_ tagIDs: [UUID]) -> [Snippet] {
        guard tagIDs.isEmpty == false else {
            return []
        }
        return store.library.snippets.filter { snippet in
            tagIDs.allSatisfy { snippet.tagIDs.contains($0) }
        }
    }

    /// 現在の絞り込み結果に含まれる未選択タグと件数を返す。
    func subTagCandidates(
        in snippets: [Snippet],
        excluding excludedTagIDs: [UUID]
    ) -> [PanelTagCandidate] {
        var countsByTagID: [UUID: Int] = [:]
        for snippet in snippets {
            for tagID in snippet.tagIDs where excludedTagIDs.contains(tagID) == false {
                countsByTagID[tagID, default: 0] += 1
            }
        }
        let tags = store.library.tags.filter { countsByTagID[$0.id] != nil }
        return orderedTags(tags, counts: countsByTagID).map {
            PanelTagCandidate(tag: $0, snippetCount: countsByTagID[$0.id] ?? 0)
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

    func allSnippets() -> [Snippet] {
        store.library.snippets.sorted {
            $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        }
    }

    func favoriteSnippets() -> [Snippet] {
        allSnippets().filter(\.isFavorite)
    }

    func toggleFavorite(_ snippetID: UUID) {
        store.toggleFavorite(id: snippetID)
    }

    // MARK: - 選択と項目列の組み立て

    private var trimmedQuery: String {
        queryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scopedListItems() -> [PanelListItem] {
        var items: [PanelListItem] = isDrilledDown ? [.backToParent] : []
        items.append(contentsOf: visibleTagCandidates.map(PanelListItem.tag))
        items.append(contentsOf: scopedSnippetItems)
        return items
    }

    private func topLevelListItems() -> [PanelListItem] {
        var items: [PanelListItem] = []
        for section in preferences.orderedEnabledSections {
            switch section {
            case .tags:
                items.append(contentsOf: visibleTagCandidates.map(PanelListItem.tag))
            case .recents:
                items += snippetItems(recentSnippets(), context: section.rawValue)
            case .allSnippets:
                items += snippetItems(allSnippets(), context: section.rawValue)
            case .favorites:
                items += snippetItems(favoriteSnippets(), context: section.rawValue)
            }
        }
        return items
    }

    private func snippetItems(_ snippets: [Snippet], context: String) -> [PanelListItem] {
        snippets.map { .snippet(emptyMatch(for: $0), context: context) }
    }

    private func globalTagCandidates() -> [PanelTagCandidate] {
        let counts = Dictionary(
            uniqueKeysWithValues: store.library.tags.map { ($0.id, snippetCount(for: $0.id)) }
        )
        return orderedTags(store.library.tags, counts: counts).map {
            PanelTagCandidate(tag: $0, snippetCount: counts[$0.id] ?? 0)
        }
    }

    private func scopedTagCandidates() -> [PanelTagCandidate] {
        subTagCandidates(in: scopedSnippets, excluding: selectedTagIDs)
    }

    private func moveVerticalSelection(by offset: Int) -> Bool {
        let selections = verticalNavigationSelections()
        guard selections.isEmpty == false else {
            return false
        }
        guard let selection, let currentIndex = selections.firstIndex(of: selection) else {
            self.selection = selections[0]
            return true
        }
        let nextIndex = min(max(0, currentIndex + offset), selections.count - 1)
        self.selection = selections[nextIndex]
        return true
    }

    /// 1行表示では連続するタグを1つの縦ナビゲーション項目として扱う。
    private func verticalNavigationSelections() -> [PanelSelection] {
        let selections = listItems.map(selection(for:))
        guard preferences.tagLayoutStyle == .horizontalStrip else {
            return selections
        }
        var didAppendTagStrip = false
        return selections.compactMap { candidateSelection in
            guard case .tag = candidateSelection else {
                return candidateSelection
            }
            guard didAppendTagStrip == false else {
                return nil
            }
            didAppendTagStrip = true
            if case .tag(let selectedTagID) = selection,
               visibleTagCandidates.contains(where: { $0.id == selectedTagID }) {
                return .tag(selectedTagID)
            }
            return visibleTagCandidates.first.map { .tag($0.id) }
        }
    }

    private func selectSnippetByOrdinal(_ index: Int) -> Bool {
        let snippets = listItems.compactMap { item -> Snippet? in
            guard case .snippet(let match, _) = item else {
                return nil
            }
            return match.snippet
        }
        guard snippets.indices.contains(index) else {
            return false
        }
        onSelectSnippet(snippets[index])
        return true
    }

    private func item(matching selection: PanelSelection) -> PanelListItem? {
        listItems.first { self.selection(for: $0) == selection }
    }

    private func selection(for item: PanelListItem) -> PanelSelection {
        switch item {
        case .backToParent:
            return .backToParent
        case .tag(let candidate):
            return .tag(candidate.tag.id)
        case .snippet(let match, let context):
            return .snippet(match.snippet.id, context: context)
        }
    }

    private func confirm(_ item: PanelListItem) {
        switch item {
        case .backToParent:
            goBackOneLevel()
        case .tag(let candidate):
            drillIntoTag(candidate.tag.id)
        case .snippet(let match, _):
            onSelectSnippet(match.snippet)
        }
    }

    /// タグ設定に従って並べる。件数が同じ場合は登録順を明示的に維持する。
    private func orderedTags(_ tags: [SnippetTag], counts: [UUID: Int]) -> [SnippetTag] {
        guard preferences.tagSortOrder == .snippetCountDescending else {
            return tags
        }
        let indices = Dictionary(uniqueKeysWithValues: store.library.tags.enumerated().map { ($0.element.id, $0.offset) })
        return tags.sorted {
            let leftCount = counts[$0.id] ?? 0
            let rightCount = counts[$1.id] ?? 0
            return leftCount == rightCount
                ? (indices[$0.id] ?? 0) < (indices[$1.id] ?? 0)
                : leftCount > rightCount
        }
    }

    private func emptyMatch(for snippet: Snippet) -> SnippetSearchMatch {
        SnippetSearchMatch(
            snippet: snippet,
            score: 0,
            titleHighlights: [],
            bodyHighlights: [],
            tagHighlights: [:]
        )
    }
}
