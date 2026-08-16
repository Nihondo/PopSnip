// MARK: - SnippetTag.swift
// スニペットに付与するタグ。色は登録時に自動割り当てされ、後から編集可能。

import Foundation

/// タグ。`id` 参照にすることで、タグ名変更が全スニペットへ自動反映される。
public struct SnippetTag: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// "#RRGGBB" 形式のカラーコード。
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
