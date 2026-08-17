// MARK: - SnippetSearchEngine.swift
// タイトル / 本文 / タグ名を対象にした部分一致検索。
// スコアは「タイトル一致 > タグ一致 > 本文一致」に usageCount / lastUsedAt の補正を加えて算出する。

import Foundation

/// 検索1件分のヒット結果。
public struct SnippetSearchMatch: Identifiable, Equatable, Sendable {
    public let snippet: Snippet
    public let score: Double
    public let titleHighlights: [HighlightRange]
    public let bodyHighlights: [HighlightRange]
    /// タグ ID ごとのヒット範囲（タグ名内のオフセット）。
    public let tagHighlights: [UUID: [HighlightRange]]

    public var id: UUID { snippet.id }
}

/// スニペット検索エンジン。
public enum SnippetSearchEngine {
    private static let titleMatchWeight = 100.0
    private static let tagMatchWeight = 50.0
    private static let bodyMatchWeight = 10.0
    private static let usageCountWeightCap = 20.0
    private static let recencyWindowDays = 10.0

    /// `query` に一致するスニペットを、`sortOrder` に従って並び替えて返す。
    /// `query` が空文字の場合は空配列を返す（呼び出し側でセクション表示に切り替える）。
    ///
    /// この形は呼び出しのたびに `tags` から検索用インデックスを組み立てる。
    /// 同じライブラリに対して繰り返し検索する場合は、インデックスを使い回せる
    /// `search(query:in:index:sortOrder:limit:now:)` を使うほうが小文字化の再計算を避けられる。
    public static func search(
        query: String,
        in snippets: [Snippet],
        tags: [SnippetTag],
        sortOrder: SearchSortOrder,
        limit: Int,
        now: Date = Date()
    ) -> [SnippetSearchMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }
        let index = SnippetSearchIndex(snippets: snippets, tags: tags)
        return search(
            query: trimmedQuery,
            in: snippets,
            index: index,
            sortOrder: sortOrder,
            limit: limit,
            now: now
        )
    }

    /// 事前構築済みの `SnippetSearchIndex` を使って検索する。
    /// タイトル・本文・タグ名の小文字化を検索のたびに繰り返さずに済むため、
    /// 同じライブラリへ何度も検索をかける呼び出し元（検索パネルなど）向け。
    public static func search(
        query: String,
        in snippets: [Snippet],
        index: SnippetSearchIndex,
        sortOrder: SearchSortOrder,
        limit: Int,
        now: Date = Date()
    ) -> [SnippetSearchMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return []
        }

        let lowerQuery = trimmedQuery.lowercased()
        let matches = snippets.compactMap { snippet in
            matchScore(lowerQuery: lowerQuery, snippet: snippet, index: index, now: now)
        }
        let sortedMatches = sort(matches, order: sortOrder)
        return Array(sortedMatches.prefix(limit))
    }

    // MARK: - スコアリング

    private static func matchScore(
        lowerQuery: String,
        snippet: Snippet,
        index: SnippetSearchIndex,
        now: Date
    ) -> SnippetSearchMatch? {
        var score = 0.0

        // インデックスに未登録のスニペット（呼び出し元が古いインデックスを渡した場合など）は
        // その場で小文字化してフォールバックし、結果の正しさを優先する。
        let texts = index.textsBySnippetID[snippet.id]
        let lowerTitle = texts?.lowerTitle ?? snippet.displayTitle.lowercased()
        let lowerBody = texts?.lowerBody ?? snippet.body.lowercased()

        let titleHighlights = findRanges(lowerQuery: lowerQuery, lowerText: lowerTitle)
        if titleHighlights.isEmpty == false {
            score += titleMatchWeight
        }

        let bodyHighlights = findRanges(lowerQuery: lowerQuery, lowerText: lowerBody)
        if bodyHighlights.isEmpty == false {
            score += bodyMatchWeight
        }

        var tagHighlights: [UUID: [HighlightRange]] = [:]
        for tagID in snippet.tagIDs {
            guard let lowerTagName = index.lowerTagNamesByTagID[tagID] else {
                continue
            }
            let ranges = findRanges(lowerQuery: lowerQuery, lowerText: lowerTagName)
            guard ranges.isEmpty == false else {
                continue
            }
            tagHighlights[tagID] = ranges
            score += tagMatchWeight
        }

        guard score > 0 else {
            return nil
        }

        score += min(Double(snippet.usageCount), usageCountWeightCap) * 0.5
        if let lastUsedAt = snippet.lastUsedAt {
            let daysSinceLastUse = now.timeIntervalSince(lastUsedAt) / 86_400
            score += max(0, recencyWindowDays - daysSinceLastUse) * 0.2
        }

        return SnippetSearchMatch(
            snippet: snippet,
            score: score,
            titleHighlights: titleHighlights,
            bodyHighlights: bodyHighlights,
            tagHighlights: tagHighlights
        )
    }

    /// 小文字化済みの `lowerText` 中で `lowerQuery` に一致する箇所をすべて返す。
    /// 呼び出し元が事前に小文字化を済ませておくことで、検索1回あたりの再計算を避ける。
    private static func findRanges(lowerQuery: String, lowerText: String) -> [HighlightRange] {
        guard lowerQuery.isEmpty == false, lowerText.isEmpty == false else {
            return []
        }

        var ranges: [HighlightRange] = []
        var searchStartIndex = lowerText.startIndex
        while
            searchStartIndex < lowerText.endIndex,
            let foundRange = lowerText.range(of: lowerQuery, range: searchStartIndex..<lowerText.endIndex)
        {
            ranges.append(NSRange(foundRange, in: lowerText))
            searchStartIndex = foundRange.upperBound
        }
        return ranges
    }

    // MARK: - 並び替え

    private static func sort(_ matches: [SnippetSearchMatch], order: SearchSortOrder) -> [SnippetSearchMatch] {
        switch order {
        case .relevance:
            return matches.sorted { $0.score > $1.score }
        case .usageCount:
            return matches.sorted { $0.snippet.usageCount > $1.snippet.usageCount }
        case .updatedAt:
            return matches.sorted { $0.snippet.updatedAt > $1.snippet.updatedAt }
        }
    }
}
