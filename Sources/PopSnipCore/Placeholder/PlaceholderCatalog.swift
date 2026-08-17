// MARK: - PlaceholderCatalog.swift
// スニペット本文中で使える `{{keyword}}` プレースホルダの一覧。
// `PlaceholderParser` / `PlaceholderExpander` の展開ロジックと、編集画面のガイダンス
// パレット（`PlaceholderPaletteView`）の両方がここを唯一の情報源として参照する。

import Foundation

/// プレースホルダの種類。`rawValue` がそのまま `{{ }}` 内のキーワード文字列になる。
public enum PlaceholderKind: String, CaseIterable, Sendable {
    case date
    case time
    case datetime
    case year
    case month
    case day
    case weekday
    case clipboard
    case selection
    case app
    case uuid
    case cursor
}

/// ガイダンスパレットでの見出し分類。
public enum PlaceholderCategory: CaseIterable, Sendable {
    case dateTime
    case context
    case other

    /// パレットのカテゴリ見出しに使う L10n キー。
    public var titleKey: String {
        switch self {
        case .dateTime: return "placeholder.category.dateTime"
        case .context: return "placeholder.category.context"
        case .other: return "placeholder.category.other"
        }
    }
}

/// 1つのプレースホルダの定義。
public struct PlaceholderDefinition: Identifiable, Sendable {
    public let kind: PlaceholderKind
    public let category: PlaceholderCategory
    /// `{{date:yyyy-MM-dd}}` のように `:` 以降の引数を受け付けるか。
    public let acceptsArgument: Bool
    /// パレットのチップに表示する名前の L10n キー。
    public let nameKey: String
    /// パレットのツールチップに表示する説明の L10n キー。
    public let descriptionKey: String

    public var id: PlaceholderKind { kind }
    public var keyword: String { kind.rawValue }
    /// パレットからのクリック挿入・ドラッグ挿入で本文へ差し込む既定のトークン文字列。
    public var token: String { "{{\(keyword)}}" }
}

/// プレースホルダ定義の一覧と、キーワード文字列からの逆引き。
public enum PlaceholderCatalog {
    public static let all: [PlaceholderDefinition] = [
        PlaceholderDefinition(
            kind: .date, category: .dateTime, acceptsArgument: true,
            nameKey: "placeholder.date.name", descriptionKey: "placeholder.date.description"
        ),
        PlaceholderDefinition(
            kind: .time, category: .dateTime, acceptsArgument: true,
            nameKey: "placeholder.time.name", descriptionKey: "placeholder.time.description"
        ),
        PlaceholderDefinition(
            kind: .datetime, category: .dateTime, acceptsArgument: true,
            nameKey: "placeholder.datetime.name", descriptionKey: "placeholder.datetime.description"
        ),
        PlaceholderDefinition(
            kind: .year, category: .dateTime, acceptsArgument: false,
            nameKey: "placeholder.year.name", descriptionKey: "placeholder.year.description"
        ),
        PlaceholderDefinition(
            kind: .month, category: .dateTime, acceptsArgument: false,
            nameKey: "placeholder.month.name", descriptionKey: "placeholder.month.description"
        ),
        PlaceholderDefinition(
            kind: .day, category: .dateTime, acceptsArgument: false,
            nameKey: "placeholder.day.name", descriptionKey: "placeholder.day.description"
        ),
        PlaceholderDefinition(
            kind: .weekday, category: .dateTime, acceptsArgument: false,
            nameKey: "placeholder.weekday.name", descriptionKey: "placeholder.weekday.description"
        ),
        PlaceholderDefinition(
            kind: .clipboard, category: .context, acceptsArgument: false,
            nameKey: "placeholder.clipboard.name", descriptionKey: "placeholder.clipboard.description"
        ),
        PlaceholderDefinition(
            kind: .selection, category: .context, acceptsArgument: false,
            nameKey: "placeholder.selection.name", descriptionKey: "placeholder.selection.description"
        ),
        PlaceholderDefinition(
            kind: .app, category: .context, acceptsArgument: false,
            nameKey: "placeholder.app.name", descriptionKey: "placeholder.app.description"
        ),
        PlaceholderDefinition(
            kind: .uuid, category: .other, acceptsArgument: false,
            nameKey: "placeholder.uuid.name", descriptionKey: "placeholder.uuid.description"
        ),
        PlaceholderDefinition(
            kind: .cursor, category: .other, acceptsArgument: false,
            nameKey: "placeholder.cursor.name", descriptionKey: "placeholder.cursor.description"
        ),
    ]

    private static let byKeyword: [String: PlaceholderDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.keyword, $0) }
    )

    /// `{{ }}` の中身から取り出したキーワード文字列から定義を引く。未知のキーワードなら nil。
    public static func definition(forKeyword keyword: String) -> PlaceholderDefinition? {
        byKeyword[keyword]
    }
}
