// MARK: - SnippetStoreTests.swift
// SnippetStore の CRUD、タグ削除時の参照整合、外部編集の遅延リロードを検証する。

import Foundation
import Testing
@testable import PopSnip

@Suite("SnippetStore", .serialized)
@MainActor
struct SnippetStoreTests {
    private func makeTemporaryStore() -> SnippetStore {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopSnipTests-\(UUID().uuidString).json")
        return SnippetStore(fileURL: temporaryURL)
    }

    @Test("スニペットを登録すると保存され、再読み込みでも残る")
    func upsertSnippetPersists() {
        let store = makeTemporaryStore()
        let snippet = Snippet(title: "テスト", body: "本文")
        store.upsertSnippet(snippet)

        let reloadedStore = SnippetStore(fileURL: store.fileURL)
        #expect(reloadedStore.library.snippets.contains { $0.id == snippet.id })
    }

    @Test("タグを削除すると、そのタグを参照していたスニペットの tagIDs からも取り除かれる")
    func deletingTagRemovesReferenceFromSnippets() {
        let store = makeTemporaryStore()
        let tag = store.createTag(name: "一時タグ")
        var snippet = Snippet(body: "本文", tagIDs: [tag.id])
        store.upsertSnippet(snippet)

        store.deleteTag(id: tag.id)

        snippet = store.library.snippets.first { $0.id == snippet.id }!
        #expect(snippet.tagIDs.contains(tag.id) == false)
        #expect(store.library.tags.contains { $0.id == tag.id } == false)
    }

    @Test("recordUsage で使用回数と最終使用日時が更新される")
    func recordUsageUpdatesUsageCountAndLastUsedAt() {
        let store = makeTemporaryStore()
        let snippet = Snippet(body: "本文")
        store.upsertSnippet(snippet)

        store.recordUsage(of: snippet.id)

        let updatedSnippet = store.library.snippets.first { $0.id == snippet.id }
        #expect(updatedSnippet?.usageCount == 1)
        #expect(updatedSnippet?.lastUsedAt != nil)
    }

    // MARK: - revision / 検索インデックス

    @Test("library を変更するすべての操作で revision が単調増加する")
    func revisionIncreasesOnEveryLibraryMutation() {
        let store = makeTemporaryStore()
        var previousRevision = store.revision

        let tag = store.createTag(name: "リビジョン確認用")
        #expect(store.revision > previousRevision)
        previousRevision = store.revision

        let snippet = Snippet(body: "本文", tagIDs: [tag.id])
        store.upsertSnippet(snippet)
        #expect(store.revision > previousRevision)
        previousRevision = store.revision

        store.recordUsage(of: snippet.id)
        #expect(store.revision > previousRevision)
        previousRevision = store.revision

        store.toggleFavorite(id: snippet.id)
        #expect(store.revision > previousRevision)
        previousRevision = store.revision

        store.deleteTag(id: tag.id)
        #expect(store.revision > previousRevision)
        previousRevision = store.revision

        store.deleteSnippet(id: snippet.id)
        #expect(store.revision > previousRevision)
    }

    @Test("外部編集を検知した再読み込みでも revision が上がり、検索インデックスが作り直される")
    func reloadIfNeededIncrementsRevisionWhenFileChangesExternally() throws {
        let store = makeTemporaryStore()
        store.upsertSnippet(Snippet(body: "初期"))
        let revisionBeforeExternalEdit = store.revision
        let indexBeforeExternalEdit = store.searchIndex()

        // 外部エディタでの書き換えを模して、ファイルを直接上書きし mtime を進める。
        let externalSnippet = Snippet(title: "外部編集タイトル", body: "外部編集本文")
        let externalLibrary = SnippetLibrary(snippets: [externalSnippet], tags: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(externalLibrary).write(to: store.fileURL)
        let futureModificationDate = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes(
            [.modificationDate: futureModificationDate],
            ofItemAtPath: store.fileURL.path
        )

        store.reloadIfNeeded()

        #expect(store.revision > revisionBeforeExternalEdit)
        #expect(store.library.snippets.map(\.id) == [externalSnippet.id])

        let indexAfterExternalEdit = store.searchIndex()
        #expect(indexBeforeExternalEdit.textsBySnippetID[externalSnippet.id] == nil)
        #expect(indexAfterExternalEdit.textsBySnippetID[externalSnippet.id]?.lowerTitle == "外部編集タイトル")
    }
}

@Suite("TagColorAssigner")
struct TagColorAssignerTests {
    @Test("既存タグが無ければパレットの先頭色を返す")
    func returnsFirstColorWhenNoExistingTags() {
        let color = TagColorAssigner.nextColor(existingTags: [])
        #expect(color == TagColorAssigner.palette.first)
    }

    @Test("既存タグが使っている色は避けて未使用色を返す")
    func avoidsColorsAlreadyInUse() {
        let usedTag = SnippetTag(name: "既存", colorHex: TagColorAssigner.palette[0])
        let color = TagColorAssigner.nextColor(existingTags: [usedTag])
        #expect(color != TagColorAssigner.palette[0])
        #expect(TagColorAssigner.palette.contains(color))
    }
}
