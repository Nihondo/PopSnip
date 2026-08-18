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

/// 検索語・タグ絞り込み・ライブラリの状態が変わっていなければ計算結果を使い回すための、
/// 最新1件だけを覚えておく軽量キャッシュ。SwiftUI の body 再評価やキー操作のたびに
/// 同じ検索/集計を繰り返さないために使う。
private struct Memoized<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    mutating func value(for key: Key, compute: () -> Value) -> Value {
        if let currentKey = self.key, currentKey == key, let currentValue = value {
            return currentValue
        }
        let computed = compute()
        self.key = key
        self.value = computed
        return computed
    }
}

/// 検索結果・タグ候補・項目列のキャッシュキー。
/// これらはいずれも「検索語 + 選択中タグ + ライブラリの版」だけで一意に決まる。
private struct PanelQueryCacheKey: Equatable {
    let trimmedQuery: String
    let selectedTagIDs: [UUID]
    let revision: Int
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
    /// 確定の視覚フィードバックのためだけに選択を動かしているあいだ true。
    /// この間はスクロール追従を抑え、以降の確定操作も受け付けない。
    @Published private(set) var isConfirmingSelection = false

    let store: SnippetStore
    let preferences: PanelPreferences
    private let onSelectSnippet: (Snippet, Bool) -> Void
    private let onCancel: () -> Void

    // MARK: - キャッシュ
    // `queryText` / `selectedTagIDs` / `store.revision` が変わらない限り、検索・集計を
    // 再実行せず前回の結果を返す。SwiftUI の body 再評価やキー操作のたびに同じ検索が
    // 何度も走るのを防ぐための最新1件キャッシュ。
    private var searchMatchesCache = Memoized<PanelQueryCacheKey, [SnippetSearchMatch]>()
    private var visibleTagCandidatesCache = Memoized<PanelQueryCacheKey, [PanelTagCandidate]>()
    private var listItemsCache = Memoized<PanelQueryCacheKey, [PanelListItem]>()
    private var allSnippetsCache = Memoized<Int, [Snippet]>()
    private var recentSnippetsCache = Memoized<Int, [Snippet]>()

    init(
        store: SnippetStore,
        preferences: PanelPreferences,
        onSelectSnippet: @escaping (Snippet, Bool) -> Void,
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
        searchMatchesCache.value(for: queryCacheKey) {
            SnippetSearchEngine.search(
                query: queryText,
                in: scopedSnippets,
                index: store.searchIndex(),
                sortOrder: preferences.searchSortOrder,
                limit: preferences.searchResultLimit
            )
        }
    }

    /// タグセクションが有効なときだけ、現在のスコープと検索語に合う候補を返す。
    var visibleTagCandidates: [PanelTagCandidate] {
        guard preferences.enabledSections.contains(.tags) else {
            return []
        }
        return visibleTagCandidatesCache.value(for: queryCacheKey) {
            let candidates = isDrilledDown ? scopedTagCandidates() : globalTagCandidates()
            guard isSearching else {
                return candidates
            }
            return candidates.filter {
                $0.tag.name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
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
        listItemsCache.value(for: queryCacheKey) {
            if isSearching || isDrilledDown {
                return scopedListItems()
            }
            return topLevelListItems()
        }
    }

    /// `listItems` 中のスニペット項目に、⌘1〜⌘9 に対応する1-based の番号を振る。
    /// `selectSnippetByOrdinal(_:)` が数えるのと同じ順序（タグ・戻る行を除いた
    /// スニペットだけの通し番号）を使うため、View 側はここを引くだけで
    /// キー操作と表示が食い違わない。
    var snippetOrdinalsByItemID: [String: Int] {
        guard preferences.isNumberKeySelectionEnabled else {
            return [:]
        }
        var result: [String: Int] = [:]
        var ordinal = 0
        for item in listItems {
            guard case .snippet = item else {
                continue
            }
            ordinal += 1
            guard ordinal <= 9 else {
                break
            }
            result[item.id] = ordinal
        }
        return result
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

    /// マウスクリックなど、キーボード選択を経ずにスニペットを確定する経路から呼ぶ。
    /// 確定した行をハイライトへ反映してから挿入を依頼する。
    func selectSnippet(_ snippet: Snippet, context: String) {
        confirmSnippetShowingHighlight(snippet, context: context)
    }

    /// キーボード選択を経ずに確定する経路（クリック・⌘数字）で、確定した行を
    /// ハイライトへ反映してから挿入を依頼する。
    private func confirmSnippetShowingHighlight(_ snippet: Snippet, context: String) {
        guard isConfirmingSelection == false else {
            return
        }
        isConfirmingSelection = true
        selection = .snippet(snippet.id, context: context)
        onSelectSnippet(snippet, true)
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
        let countsByTagID = tagSnippetCounts(in: snippets, excluding: excludedTagIDs)
        let tags = store.library.tags.filter { countsByTagID[$0.id] != nil }
        return orderedTags(tags, counts: countsByTagID, snippets: snippets).map {
            PanelTagCandidate(tag: $0, snippetCount: countsByTagID[$0.id] ?? 0)
        }
    }

    func snippetCount(for tagID: UUID) -> Int {
        store.library.snippets.filter { $0.tagIDs.contains(tagID) }.count
    }

    /// タグ ID ごとのスニペット件数を、全スニペットを1回だけ走査して集計する。
    /// `tags.count × snippets.count` の総当たりを避けるための共通処理。
    private func tagSnippetCounts(
        in snippets: [Snippet],
        excluding excludedTagIDs: [UUID]
    ) -> [UUID: Int] {
        var countsByTagID: [UUID: Int] = [:]
        for snippet in snippets {
            for tagID in snippet.tagIDs where excludedTagIDs.contains(tagID) == false {
                countsByTagID[tagID, default: 0] += 1
            }
        }
        return countsByTagID
    }

    func recentSnippets() -> [Snippet] {
        recentSnippetsCache.value(for: store.revision) {
            Array(
                store.library.snippets
                    .filter { $0.lastUsedAt != nil }
                    .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
                    .prefix(preferences.recentsLimit)
            )
        }
    }

    /// 表示名のロケール順にソートしたスニペット一覧。`favoriteSnippets()` もこの結果を再利用する。
    func allSnippets() -> [Snippet] {
        allSnippetsCache.value(for: store.revision) {
            store.library.snippets.sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
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

    /// 検索結果・タグ候補・項目列のキャッシュを識別するキー。
    private var queryCacheKey: PanelQueryCacheKey {
        PanelQueryCacheKey(trimmedQuery: trimmedQuery, selectedTagIDs: selectedTagIDs, revision: store.revision)
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
        // `subTagCandidates` と異なり、件数 0 のタグもトップレベルでは表示し続ける必要があるため、
        // 全タグを対象に単一走査の件数辞書から引く（欠落キーは 0 件として扱う）。
        let counts = tagSnippetCounts(in: store.library.snippets, excluding: [])
        return orderedTags(store.library.tags, counts: counts, snippets: store.library.snippets).map {
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
        let snippets = listItems.compactMap { item -> (Snippet, String)? in
            guard case .snippet(let match, let context) = item else {
                return nil
            }
            return (match.snippet, context)
        }
        guard snippets.indices.contains(index) else {
            return false
        }
        let (snippet, context) = snippets[index]
        confirmSnippetShowingHighlight(snippet, context: context)
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
            onSelectSnippet(match.snippet, false)
        }
    }

    /// タグ設定に従って並べ、比較値が同じタグは登録順を維持する。
    private func orderedTags(
        _ tags: [SnippetTag],
        counts: [UUID: Int],
        snippets: [Snippet]
    ) -> [SnippetTag] {
        let indices = registrationIndicesByTagID()
        switch preferences.tagSortOrder {
        case .registrationOrder:
            return tags
        case .snippetCountDescending:
            return tags.sorted {
                precedesBySnippetCount($0, $1, counts: counts, indices: indices)
            }
        case .recentlyUsed:
            let dates = lastUsedDatesByTagID(in: snippets)
            return tags.sorted {
                precedesByRecentUse($0, $1, dates: dates, indices: indices)
            }
        }
    }

    private func precedesBySnippetCount(
        _ leftTag: SnippetTag,
        _ rightTag: SnippetTag,
        counts: [UUID: Int],
        indices: [UUID: Int]
    ) -> Bool {
        let leftCount = counts[leftTag.id] ?? 0
        let rightCount = counts[rightTag.id] ?? 0
        return leftCount == rightCount
            ? precedesByRegistration(leftTag, rightTag, indices: indices)
            : leftCount > rightCount
    }

    private func precedesByRecentUse(
        _ leftTag: SnippetTag,
        _ rightTag: SnippetTag,
        dates: [UUID: Date],
        indices: [UUID: Int]
    ) -> Bool {
        let leftDate = dates[leftTag.id] ?? .distantPast
        let rightDate = dates[rightTag.id] ?? .distantPast
        return leftDate == rightDate
            ? precedesByRegistration(leftTag, rightTag, indices: indices)
            : leftDate > rightDate
    }

    private func registrationIndicesByTagID() -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: store.library.tags.enumerated().map { ($0.element.id, $0.offset) })
    }

    private func lastUsedDatesByTagID(in snippets: [Snippet]) -> [UUID: Date] {
        var datesByTagID: [UUID: Date] = [:]
        for snippet in snippets {
            guard let lastUsedAt = snippet.lastUsedAt else {
                continue
            }
            for tagID in snippet.tagIDs where lastUsedAt > (datesByTagID[tagID] ?? .distantPast) {
                datesByTagID[tagID] = lastUsedAt
            }
        }
        return datesByTagID
    }

    private func precedesByRegistration(
        _ leftTag: SnippetTag,
        _ rightTag: SnippetTag,
        indices: [UUID: Int]
    ) -> Bool {
        (indices[leftTag.id] ?? 0) < (indices[rightTag.id] ?? 0)
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
