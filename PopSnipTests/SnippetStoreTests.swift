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
