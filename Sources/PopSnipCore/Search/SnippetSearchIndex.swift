// MARK: - SnippetSearchIndex.swift
// 検索対象テキストの小文字化を、ライブラリ更新のたびに1回だけ済ませておくためのインデックス。
// `SnippetSearchEngine.findRanges` は本来キーストロークごとに呼び出されるため、
// タイトル・本文・タグ名の `lowercased()` をここで前計算し、検索1回あたりのアロケーションを避ける。

import Foundation

/// スニペット検索用の事前計算済みインデックス。
/// `SnippetStore` がライブラリの変更を検知して再構築し、`SnippetSearchEngine` に渡す。
public struct SnippetSearchIndex: Sendable {
    struct SnippetText {
        let lowerTitle: String
        let lowerBody: String
    }

    let textsBySnippetID: [UUID: SnippetText]
    let lowerTagNamesByTagID: [UUID: String]

    /// 空のインデックス。
    public static let empty = SnippetSearchIndex(snippets: [], tags: [])

    /// `snippets` と `tags` を1回ずつ走査して、小文字化済みテキストの辞書を構築する。
    public init(snippets: [Snippet], tags: [SnippetTag]) {
        var texts: [UUID: SnippetText] = [:]
        texts.reserveCapacity(snippets.count)
        for snippet in snippets {
            texts[snippet.id] = SnippetText(
                lowerTitle: snippet.displayTitle.lowercased(),
                lowerBody: snippet.body.lowercased()
            )
        }
        self.textsBySnippetID = texts

        var lowerNames: [UUID: String] = [:]
        lowerNames.reserveCapacity(tags.count)
        for tag in tags {
            lowerNames[tag.id] = tag.name.lowercased()
        }
        self.lowerTagNamesByTagID = lowerNames
    }
}
