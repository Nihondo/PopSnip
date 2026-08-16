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

        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let matches = snippets.compactMap { snippet in
            matchScore(query: trimmedQuery, snippet: snippet, tagsByID: tagsByID, now: now)
        }
        let sortedMatches = sort(matches, order: sortOrder)
        return Array(sortedMatches.prefix(limit))
    }

    // MARK: - スコアリング

    private static func matchScore(
        query: String,
        snippet: Snippet,
        tagsByID: [UUID: SnippetTag],
        now: Date
    ) -> SnippetSearchMatch? {
        var score = 0.0

        let titleHighlights = findRanges(of: query, in: snippet.displayTitle)
        if titleHighlights.isEmpty == false {
            score += titleMatchWeight
        }

        let bodyHighlights = findRanges(of: query, in: snippet.body)
        if bodyHighlights.isEmpty == false {
            score += bodyMatchWeight
        }

        var tagHighlights: [UUID: [HighlightRange]] = [:]
        for tagID in snippet.tagIDs {
            guard let tag = tagsByID[tagID] else {
                continue
            }
            let ranges = findRanges(of: query, in: tag.name)
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

    /// `text` 中で `query`（大文字小文字を無視）に一致する箇所をすべて返す。
    private static func findRanges(of query: String, in text: String) -> [HighlightRange] {
        guard query.isEmpty == false, text.isEmpty == false else {
            return []
        }
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()

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
