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
