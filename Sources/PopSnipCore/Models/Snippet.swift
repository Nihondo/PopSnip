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
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String,
        tagIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        usageCount: Int = 0,
        lastUsedAt: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
        self.isFavorite = isFavorite
    }

    /// 表示名。タイトルが空/未設定の場合は本文の先頭行を使う。
    public var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let firstLine = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return String(firstLine)
    }

    // `isFavorite` は後から追加したフィールドのため、既存の snippets.json（このキーを持たない）を
    // 壊さないよう decode 側だけ手動実装する（`decodeIfPresent(...) ?? false` でキー欠落を許容）。
    // `encode(to:)` はプロパティ構成が CodingKeys と一致していればコンパイラ合成のままでよい。
    private enum CodingKeys: String, CodingKey {
        case id, title, body, tagIDs, createdAt, updatedAt, usageCount, lastUsedAt, isFavorite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        tagIDs = try container.decode([UUID].self, forKey: .tagIDs)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        usageCount = try container.decode(Int.self, forKey: .usageCount)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}
