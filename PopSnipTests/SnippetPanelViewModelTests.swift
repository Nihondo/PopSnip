// MARK: - SnippetPanelViewModelTests.swift
// クリック・⌘数字での確定時に選択ハイライトが正しく反映されることを検証する。

import Foundation
import Testing
@testable import PopSnip

@Suite("SnippetPanelViewModel", .serialized)
@MainActor
struct SnippetPanelViewModelTests {
    private func makeStore() -> SnippetStore {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopSnipTests-\(UUID().uuidString).json")
        return SnippetStore(fileURL: temporaryURL)
    }

    private func makeViewModel(
        store: SnippetStore,
        preferences: PanelPreferences = .default,
        onSelectSnippet: @escaping (Snippet, Bool) -> Void = { _, _ in },
        onCancel: @escaping () -> Void = {}
    ) -> SnippetPanelViewModel {
        SnippetPanelViewModel(
            store: store,
            preferences: preferences,
            onSelectSnippet: onSelectSnippet,
            onCancel: onCancel
        )
    }

    @Test("selectSnippet(_:context:) は選択をその行へ移し、確定演出中フラグを立てる")
    func selectSnippetUpdatesSelectionAndFlagsConfirmation() {
        let store = makeStore()
        let snippet = Snippet(title: "テスト", body: "本文")
        store.upsertSnippet(snippet)

        var receivedSnippet: Snippet?
        var receivedWaitsForHighlight: Bool?
        let viewModel = makeViewModel(store: store) { selected, waitsForHighlight in
            receivedSnippet = selected
            receivedWaitsForHighlight = waitsForHighlight
        }

        viewModel.selectSnippet(snippet, context: "allSnippets")

        #expect(viewModel.isSnippetSelected(snippet.id, context: "allSnippets"))
        #expect(viewModel.isConfirmingSelection)
        #expect(receivedSnippet?.id == snippet.id)
        #expect(receivedWaitsForHighlight == true)
    }

    @Test("同じスニペットが複数セクションにあるとき、クリックしたセクション側だけがハイライトされる")
    func selectSnippetHighlightsOnlyTheClickedSection() {
        let store = makeStore()
        var snippet = Snippet(title: "お気に入り", body: "本文")
        snippet.isFavorite = true
        store.upsertSnippet(snippet)
        store.recordUsage(of: snippet.id)

        let viewModel = makeViewModel(store: store)

        // favorites / allSnippets 両方に同じスニペットが現れる状況で、
        // allSnippets 側の行をクリックしたことを模す。
        viewModel.selectSnippet(snippet, context: PanelSection.allSnippets.rawValue)

        #expect(viewModel.isSnippetSelected(snippet.id, context: PanelSection.allSnippets.rawValue))
        #expect(viewModel.isSnippetSelected(snippet.id, context: PanelSection.favorites.rawValue) == false)
    }

    @Test("⌘数字キーでの確定でも選択がその行へ移る")
    func digitKeyConfirmationUpdatesSelection() {
        let store = makeStore()
        let snippet = Snippet(title: "テスト", body: "本文")
        store.upsertSnippet(snippet)

        var receivedWaitsForHighlight: Bool?
        let viewModel = makeViewModel(store: store) { _, waitsForHighlight in
            receivedWaitsForHighlight = waitsForHighlight
        }

        let handled = viewModel.handleKeyEvent(.digit(1))

        #expect(handled)
        #expect(viewModel.isSnippetSelected(snippet.id, context: PanelSection.allSnippets.rawValue))
        #expect(receivedWaitsForHighlight == true)
    }

    @Test("確定演出中に再度確定操作をしても onSelectSnippet は再発火しない")
    func confirmingSelectionIgnoresSecondConfirmation() {
        let store = makeStore()
        let snippetA = Snippet(title: "A", body: "本文A")
        let snippetB = Snippet(title: "B", body: "本文B")
        store.upsertSnippet(snippetA)
        store.upsertSnippet(snippetB)

        var callCount = 0
        let viewModel = makeViewModel(store: store) { _, _ in
            callCount += 1
        }

        viewModel.selectSnippet(snippetA, context: "allSnippets")
        viewModel.selectSnippet(snippetB, context: "allSnippets")

        #expect(callCount == 1)
        #expect(viewModel.isSnippetSelected(snippetA.id, context: "allSnippets"))
        #expect(viewModel.isSnippetSelected(snippetB.id, context: "allSnippets") == false)
    }

    @Test("Enter による確定は selection を変更せず、確定演出フラグも立てない")
    func confirmSelectionDoesNotFlagHighlightWait() {
        let store = makeStore()
        let snippet = Snippet(title: "テスト", body: "本文")
        store.upsertSnippet(snippet)

        var receivedWaitsForHighlight: Bool?
        let viewModel = makeViewModel(store: store) { _, waitsForHighlight in
            receivedWaitsForHighlight = waitsForHighlight
        }
        viewModel.resetSelectionForContentChange()

        let confirmed = viewModel.confirmSelection()

        #expect(confirmed)
        #expect(receivedWaitsForHighlight == false)
        #expect(viewModel.isConfirmingSelection == false)
    }

    @Test("⌘1〜⌘9の番号は、トップレベル閲覧でもセクションをまたいで通し番号になる")
    func snippetOrdinalsSpanSectionsInTopLevelBrowsing() {
        let store = makeStore()
        // allSnippets はタイトルの辞書順で並ぶため、順序を明確にするため意図的に
        // "Apple" < "Banana" となるタイトルを使う。
        var favorite = Snippet(title: "Apple", body: "本文")
        favorite.isFavorite = true
        let other = Snippet(title: "Banana", body: "本文")
        store.upsertSnippet(favorite)
        store.upsertSnippet(other)

        let viewModel = makeViewModel(store: store)

        let favoriteItemID = PanelListItem.snippetItemID(favorite.id, context: PanelSection.favorites.rawValue)
        let otherItemID = PanelListItem.snippetItemID(other.id, context: PanelSection.allSnippets.rawValue)
        let favoriteInAllItemID = PanelListItem.snippetItemID(favorite.id, context: PanelSection.allSnippets.rawValue)

        let ordinals = viewModel.snippetOrdinalsByItemID
        #expect(ordinals[favoriteItemID] == 1)
        #expect(ordinals[favoriteInAllItemID] == 2)
        #expect(ordinals[otherItemID] == 3)
    }

    @Test("番号キー選択が無効なときは番号を振らない")
    func snippetOrdinalsAreEmptyWhenNumberKeySelectionDisabled() {
        let store = makeStore()
        store.upsertSnippet(Snippet(title: "テスト", body: "本文"))
        var preferences = PanelPreferences.default
        preferences.isNumberKeySelectionEnabled = false

        let viewModel = makeViewModel(store: store, preferences: preferences)

        #expect(viewModel.snippetOrdinalsByItemID.isEmpty)
    }

    @Test("10件目以降のスニペットには番号を振らない（⌘0〜⌘9の範囲外）")
    func snippetOrdinalsCapAtNine() {
        let store = makeStore()
        let snippets = (1...10).map { Snippet(title: "スニペット\($0)", body: "本文") }
        snippets.forEach(store.upsertSnippet)

        let viewModel = makeViewModel(store: store)

        let ordinals = viewModel.snippetOrdinalsByItemID
        #expect(ordinals.count == 9)
        let tenthItemID = PanelListItem.snippetItemID(snippets[9].id, context: PanelSection.allSnippets.rawValue)
        #expect(ordinals[tenthItemID] == nil)
    }
}
