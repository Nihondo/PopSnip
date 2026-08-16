// MARK: - Snippet.swift
// スニペット1件を表すデータモデル。
// タイトルは省略可能で、省略時は本文の先頭行を表示名として扱う（呼び出し側の責務）。

import Foundation

/// 登録済みスニペット。タグ ID の配列で `SnippetTag` を参照する（タグ方式・フラット構造）。
public struct Snippet: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String?
    public var body: String
    public var tagIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
    public var usageCount: Int
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String,
        tagIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        usageCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
    }

    /// 表示名。タイトルが空/未設定の場合は本文の先頭行を使う。
    public var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let firstLine = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return String(firstLine)
    }
}
