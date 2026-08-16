// MARK: - SnippetLibrary.swift
// snippets.json のルート構造。schemaVersion を持たせ、将来のマイグレーションに備える。

import Foundation

/// スニペットとタグ全体を保持するライブラリ。ディスク上は単一の JSON ファイルとして永続化する。
public struct SnippetLibrary: Codable, Equatable, Sendable {
    /// 現行スキーマのバージョン。フォーマット変更時はここを進め、`SnippetStore` 側でマイグレーションする。
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var snippets: [Snippet]
    public var tags: [SnippetTag]

    public init(
        schemaVersion: Int = SnippetLibrary.currentSchemaVersion,
        snippets: [Snippet] = [],
        tags: [SnippetTag] = []
    ) {
        self.schemaVersion = schemaVersion
        self.snippets = snippets
        self.tags = tags
    }

    /// 空のライブラリ（初回起動時のデフォルト）。
    public static let empty = SnippetLibrary()
}
