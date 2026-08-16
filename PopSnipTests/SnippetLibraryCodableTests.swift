// MARK: - SnippetLibraryCodableTests.swift
// SnippetLibrary の JSON ラウンドトリップと、タグ ID 参照の整合性を検証する。

import Foundation
import Testing
@testable import PopSnip

@Suite("SnippetLibrary の Codable ラウンドトリップ")
struct SnippetLibraryCodableTests {
    @Test("エンコード→デコードで内容が完全一致する")
    func roundTripPreservesContent() throws {
        // ISO8601 エンコードは小数点以下の秒を保持しないため、比較用の日時は整数秒に揃える
        // （createdAt/updatedAt を既定の Date() のままにすると、丸められた decode 後の値と
        //  一致しなくなり無関係な差分でテストが落ちる）。
        let wholeSecondDate = Date(timeIntervalSince1970: 1_700_000_000)
        let tag = SnippetTag(name: "Linux", colorHex: "#7799DD")
        let snippet = Snippet(
            title: "systemctl status",
            body: "systemctl status ",
            tagIDs: [tag.id],
            createdAt: wholeSecondDate,
            updatedAt: wholeSecondDate,
            usageCount: 3,
            lastUsedAt: wholeSecondDate
        )
        let library = SnippetLibrary(snippets: [snippet], tags: [tag])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(library)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedLibrary = try decoder.decode(SnippetLibrary.self, from: data)

        #expect(decodedLibrary == library)
    }

    @Test("タグ ID 参照は decode 後も維持される")
    func tagReferenceIntegrityIsPreserved() throws {
        let tagA = SnippetTag(name: "Mail", colorHex: "#16A34A")
        let tagB = SnippetTag(name: "挨拶", colorHex: "#F59E0B")
        let snippet = Snippet(body: "お世話になっております。", tagIDs: [tagA.id, tagB.id])
        let library = SnippetLibrary(snippets: [snippet], tags: [tagA, tagB])

        let data = try JSONEncoder().encode(library)
        let decodedLibrary = try JSONDecoder().decode(SnippetLibrary.self, from: data)

        let decodedSnippet = try #require(decodedLibrary.snippets.first)
        #expect(decodedSnippet.tagIDs == [tagA.id, tagB.id])
        #expect(decodedLibrary.tags.map(\.id).contains(tagA.id))
        #expect(decodedLibrary.tags.map(\.id).contains(tagB.id))
    }

    @Test("displayTitle はタイトル未設定時に本文の先頭行を使う")
    func displayTitleFallsBackToFirstLineOfBody() {
        let snippet = Snippet(body: "1行目\n2行目")
        #expect(snippet.displayTitle == "1行目")
    }
}
