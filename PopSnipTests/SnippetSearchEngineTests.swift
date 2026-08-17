// MARK: - SnippetSearchEngineTests.swift
// 検索スコアリング（タイトル一致 > タグ一致 > 本文一致、usageCount/lastUsedAt 補正）を検証する。

import Foundation
import Testing
@testable import PopSnip

@Suite("SnippetSearchEngine のスコアリング")
struct SnippetSearchEngineTests {
    @Test("空クエリでは結果を返さない")
    func emptyQueryReturnsNoResults() {
        let snippet = Snippet(title: "ssh", body: "ssh user@host")
        let results = SnippetSearchEngine.search(
            query: "",
            in: [snippet],
            tags: [],
            sortOrder: .relevance,
            limit: 10
        )
        #expect(results.isEmpty)
    }

    @Test("タイトル一致は本文一致よりスコアが高い")
    func titleMatchScoresHigherThanBodyMatch() {
        let titleMatch = Snippet(title: "ssh 接続", body: "何も一致しない本文")
        let bodyMatch = Snippet(title: "無関係", body: "ssh -i key user@host")

        let results = SnippetSearchEngine.search(
            query: "ssh",
            in: [bodyMatch, titleMatch],
            tags: [],
            sortOrder: .relevance,
            limit: 10
        )

        #expect(results.count == 2)
        #expect(results.first?.snippet.id == titleMatch.id)
    }

    @Test("タグ名一致でもヒットし、タグハイライトが記録される")
    func tagNameMatchIsIncludedWithHighlight() {
        let tag = SnippetTag(name: "AWS", colorHex: "#7799DD")
        let snippet = Snippet(title: "デプロイ", body: "本文には含まれない", tagIDs: [tag.id])

        let results = SnippetSearchEngine.search(
            query: "aws",
            in: [snippet],
            tags: [tag],
            sortOrder: .relevance,
            limit: 10
        )

        let match = try? #require(results.first)
        #expect(match?.tagHighlights[tag.id]?.isEmpty == false)
    }

    @Test("limit を超える件数は切り詰められる")
    func resultsAreTruncatedToLimit() {
        let snippets = (0..<10).map { index in
            Snippet(title: "snippet \(index)", body: "body")
        }
        let results = SnippetSearchEngine.search(
            query: "snippet",
            in: snippets,
            tags: [],
            sortOrder: .relevance,
            limit: 3
        )
        #expect(results.count == 3)
    }

    @Test("usageCount の並び順ではスコアではなく使用回数を優先する")
    func usageCountSortOrderPrioritizesUsageCount() {
        let lessUsed = Snippet(title: "snippet", body: "body", usageCount: 1)
        let moreUsed = Snippet(title: "snippet", body: "body", usageCount: 50)

        let results = SnippetSearchEngine.search(
            query: "snippet",
            in: [lessUsed, moreUsed],
            tags: [],
            sortOrder: .usageCount,
            limit: 10
        )

        #expect(results.first?.snippet.id == moreUsed.id)
    }
}

@Suite("タグ候補とパネル選択", .serialized)
@MainActor
struct SnippetPanelTagNavigationTests {
    @Test("検索語に部分一致するタグ候補だけを大文字小文字を無視して残す")
    func queryFiltersTagCandidates() {
        let youtube = SnippetTag(name: "YouTube", colorHex: "#7799DD")
        let prompt = SnippetTag(name: "prompt", colorHex: "#16A34A")
        let snippet = Snippet(body: "video", tagIDs: [youtube.id])
        let viewModel = makeViewModel(tags: [youtube, prompt], snippets: [snippet])

        viewModel.queryText = "YOU"
        viewModel.resetSelectionForContentChange()

        #expect(viewModel.visibleTagCandidates.map(\.id) == [youtube.id])
        #expect(viewModel.searchMatches.map(\.snippet.id) == [snippet.id])
    }

    @Test("タグ絞り込み中の検索は現在のスコープ内だけを対象にする")
    func searchUsesSelectedTagScope() {
        let prompt = SnippetTag(name: "prompt", colorHex: "#16A34A")
        let youtube = SnippetTag(name: "youtube", colorHex: "#7799DD")
        let scoped = Snippet(body: "scoped", tagIDs: [prompt.id, youtube.id])
        let outside = Snippet(body: "outside", tagIDs: [youtube.id])
        let viewModel = makeViewModel(tags: [prompt, youtube], snippets: [scoped, outside])

        viewModel.drillIntoTag(prompt.id)
        viewModel.queryText = "you"
        viewModel.resetSelectionForContentChange()

        #expect(viewModel.visibleTagCandidates.map(\.id) == [youtube.id])
        #expect(viewModel.searchMatches.map(\.snippet.id) == [scoped.id])
    }

    @Test("タグ選択後は選択済みタグを除外し、絞り込み結果内のタグだけを残す")
    func drillDownShowsOnlyUnselectedTagsFromScopedSnippets() {
        let youtube = SnippetTag(name: "youtube", colorHex: "#7799DD")
        let prompt = SnippetTag(name: "prompt", colorHex: "#16A34A")
        let ffmpeg = SnippetTag(name: "ffmpeg", colorHex: "#F59E0B")
        let suno = SnippetTag(name: "suno", colorHex: "#EF4444")
        let scoped = Snippet(body: "music", tagIDs: [youtube.id, suno.id])
        let unrelatedPrompt = Snippet(body: "prompt", tagIDs: [prompt.id])
        let unrelatedFFmpeg = Snippet(body: "video", tagIDs: [ffmpeg.id])
        let viewModel = makeViewModel(
            tags: [youtube, prompt, ffmpeg, suno],
            snippets: [scoped, unrelatedPrompt, unrelatedFFmpeg]
        )

        viewModel.drillIntoTag(suno.id)

        #expect(viewModel.visibleTagCandidates.map(\.id) == [youtube.id])
        #expect(viewModel.visibleTagCandidates.contains { $0.id == suno.id } == false)
        #expect(viewModel.selection == .backToParent)
    }

    @Test("検索中のタグを確定すると検索語を消して絞り込みに追加する")
    func confirmingSearchTagStartsDrillDown() {
        let youtube = SnippetTag(name: "youtube", colorHex: "#7799DD")
        let snippet = Snippet(body: "video", tagIDs: [youtube.id])
        let viewModel = makeViewModel(tags: [youtube], snippets: [snippet])
        viewModel.queryText = "you"
        viewModel.resetSelectionForContentChange()

        #expect(viewModel.confirmSelection())
        #expect(viewModel.queryText.isEmpty)
        #expect(viewModel.selectedTagIDs == [youtube.id])
        #expect(viewModel.selection == .backToParent)
    }

    @Test("Tabと左右キーはタグ候補の端で循環する")
    func tagNavigationWrapsAtEdges() {
        let first = SnippetTag(name: "first", colorHex: "#7799DD")
        let second = SnippetTag(name: "second", colorHex: "#16A34A")
        let viewModel = makeViewModel(tags: [first, second], snippets: [])

        #expect(viewModel.selection == .tag(first.id))
        #expect(viewModel.handleKeyEvent(.tabBackward))
        #expect(viewModel.selection == .tag(second.id))
        #expect(viewModel.handleKeyEvent(.arrowRight))
        #expect(viewModel.selection == .tag(first.id))
    }

    @Test("タグ候補が1件なら循環しても同じタグを保つ")
    func singleTagNavigationKeepsSelection() {
        let onlyTag = SnippetTag(name: "only", colorHex: "#7799DD")
        let viewModel = makeViewModel(tags: [onlyTag], snippets: [])

        #expect(viewModel.handleKeyEvent(.tabForward))
        #expect(viewModel.selection == .tag(onlyTag.id))
    }

    @Test("タグ候補が無い場合はTabをパネル側で消費しない")
    func tabIsNotConsumedWithoutTagCandidates() {
        let snippet = Snippet(title: "snippet", body: "body")
        let preferences = PanelPreferences(enabledSections: [.allSnippets])
        let viewModel = makeViewModel(tags: [], snippets: [snippet], preferences: preferences)

        #expect(viewModel.handleKeyEvent(.tabForward) == false)
        #expect(viewModel.selection == .snippet(snippet.id, context: PanelSection.allSnippets.rawValue))
    }

    @Test("1行表示の上下キーはタグ群を1行として扱う")
    func horizontalLayoutCollapsesTagsForVerticalNavigation() {
        let first = SnippetTag(name: "first", colorHex: "#7799DD")
        let second = SnippetTag(name: "second", colorHex: "#16A34A")
        let snippet = Snippet(title: "snippet", body: "body")
        let viewModel = makeViewModel(tags: [first, second], snippets: [snippet])

        #expect(viewModel.handleKeyEvent(.arrowDown))
        #expect(viewModel.selection == .snippet(snippet.id, context: PanelSection.allSnippets.rawValue))
        #expect(viewModel.handleKeyEvent(.arrowUp))
        #expect(viewModel.selection == .tag(first.id))
    }

    @Test("縦一覧表示の下キーは次のタグ行へ移動する")
    func verticalLayoutMovesThroughTagRows() {
        let first = SnippetTag(name: "first", colorHex: "#7799DD")
        let second = SnippetTag(name: "second", colorHex: "#16A34A")
        let preferences = PanelPreferences(tagLayoutStyle: .verticalList)
        let viewModel = makeViewModel(tags: [first, second], snippets: [], preferences: preferences)

        #expect(viewModel.handleKeyEvent(.arrowDown))
        #expect(viewModel.selection == .tag(second.id))
    }

    @Test("検索中のタグ候補は⌘1のスニペット番号に数えない")
    func numberSelectionIgnoresTagCandidates() {
        let youtube = SnippetTag(name: "youtube", colorHex: "#7799DD")
        let snippet = Snippet(body: "video", tagIDs: [youtube.id])
        var selectedSnippetID: UUID?
        let viewModel = makeViewModel(
            tags: [youtube],
            snippets: [snippet],
            onSelectSnippet: { selectedSnippetID = $0.id }
        )
        viewModel.queryText = "you"
        viewModel.resetSelectionForContentChange()

        #expect(viewModel.handleKeyEvent(.digit(1)))
        #expect(selectedSnippetID == snippet.id)
    }

    @Test("タグセクションを無効にしてもスニペットのタグ名検索は有効")
    func hiddenTagSectionStillSearchesSnippetTagNames() {
        let youtube = SnippetTag(name: "youtube", colorHex: "#7799DD")
        let snippet = Snippet(body: "video", tagIDs: [youtube.id])
        let preferences = PanelPreferences(enabledSections: [.allSnippets])
        let viewModel = makeViewModel(tags: [youtube], snippets: [snippet], preferences: preferences)
        viewModel.queryText = "you"
        viewModel.resetSelectionForContentChange()

        #expect(viewModel.visibleTagCandidates.isEmpty)
        #expect(viewModel.searchMatches.map(\.snippet.id) == [snippet.id])
    }

    @Test("最近使った順はタグを持つスニペットの最終使用日時を使い、未使用タグは登録順で末尾に置く")
    func recentlyUsedTagOrderUsesLatestSnippetUsage() {
        let firstUnused = SnippetTag(name: "first-unused", colorHex: "#7799DD")
        let older = SnippetTag(name: "older", colorHex: "#16A34A")
        let newer = SnippetTag(name: "newer", colorHex: "#F59E0B")
        let lastUnused = SnippetTag(name: "last-unused", colorHex: "#EF4444")
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let snippets = [
            Snippet(body: "old", tagIDs: [older.id], lastUsedAt: oldDate),
            Snippet(body: "new", tagIDs: [newer.id], lastUsedAt: newDate)
        ]
        let preferences = PanelPreferences(tagSortOrder: .recentlyUsed)
        let viewModel = makeViewModel(
            tags: [firstUnused, older, newer, lastUnused],
            snippets: snippets,
            preferences: preferences
        )

        #expect(viewModel.visibleTagCandidates.map(\.id) == [newer.id, older.id, firstUnused.id, lastUnused.id])
    }

    @Test("絞り込み中の最近使った順は現在のスニペット範囲だけで計算する")
    func recentlyUsedTagOrderUsesCurrentDrillDownScope() {
        let prompt = SnippetTag(name: "prompt", colorHex: "#16A34A")
        let youtube = SnippetTag(name: "youtube", colorHex: "#7799DD")
        let suno = SnippetTag(name: "suno", colorHex: "#EF4444")
        let scopedOld = Snippet(
            body: "scoped-old",
            tagIDs: [prompt.id, youtube.id],
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        )
        let scopedNew = Snippet(
            body: "scoped-new",
            tagIDs: [prompt.id, suno.id],
            lastUsedAt: Date(timeIntervalSince1970: 2_000)
        )
        let globallyNewestYoutube = Snippet(
            body: "outside",
            tagIDs: [youtube.id],
            lastUsedAt: Date(timeIntervalSince1970: 3_000)
        )
        let preferences = PanelPreferences(tagSortOrder: .recentlyUsed)
        let viewModel = makeViewModel(
            tags: [prompt, youtube, suno],
            snippets: [scopedOld, scopedNew, globallyNewestYoutube],
            preferences: preferences
        )

        viewModel.drillIntoTag(prompt.id)

        #expect(viewModel.visibleTagCandidates.map(\.id) == [suno.id, youtube.id])
    }

    private func makeViewModel(
        tags: [SnippetTag],
        snippets: [Snippet],
        preferences: PanelPreferences = .default,
        onSelectSnippet: @escaping (Snippet) -> Void = { _ in }
    ) -> SnippetPanelViewModel {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopSnipPanelTests-\(UUID().uuidString).json")
        let store = SnippetStore(fileURL: fileURL)
        tags.forEach(store.upsertTag)
        snippets.forEach(store.upsertSnippet)
        return SnippetPanelViewModel(
            store: store,
            preferences: preferences,
            onSelectSnippet: onSelectSnippet,
            onCancel: {}
        )
    }
}

@Suite("タグ表示設定", .serialized)
struct TagLayoutSettingsTests {
    @Test("タグ表示は1行表示が既定で、縦一覧を保存復元できる")
    func tagLayoutStyleDefaultsAndRoundTrips() throws {
        let suiteName = "PopSnipTagLayoutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppSettingsResolver.resolvePanelPreferences(userDefaults: defaults).tagLayoutStyle == .horizontalStrip)

        var preferences = PanelPreferences.default
        preferences.tagLayoutStyle = .verticalList
        AppSettingsResolver.savePanelPreferences(preferences, userDefaults: defaults)
        #expect(AppSettingsResolver.resolvePanelPreferences(userDefaults: defaults).tagLayoutStyle == .verticalList)

        defaults.set("invalid", forKey: UserDefaultsKeys.panelTagLayoutStyle)
        #expect(AppSettingsResolver.resolvePanelPreferences(userDefaults: defaults).tagLayoutStyle == .horizontalStrip)
    }

    @Test("タグの最近使った順を保存復元でき、不正値は登録順へ戻る")
    func recentlyUsedTagOrderRoundTripsAndFallsBack() throws {
        let suiteName = "PopSnipTagSortOrderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppSettingsResolver.resolvePanelPreferences(userDefaults: defaults).tagSortOrder == .registrationOrder)

        var preferences = PanelPreferences.default
        preferences.tagSortOrder = .recentlyUsed
        AppSettingsResolver.savePanelPreferences(preferences, userDefaults: defaults)
        #expect(AppSettingsResolver.resolvePanelPreferences(userDefaults: defaults).tagSortOrder == .recentlyUsed)

        defaults.set("invalid", forKey: UserDefaultsKeys.panelTagSortOrder)
        #expect(AppSettingsResolver.resolvePanelPreferences(userDefaults: defaults).tagSortOrder == .registrationOrder)
    }
}
