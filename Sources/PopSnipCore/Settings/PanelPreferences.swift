// MARK: - PanelPreferences.swift
// パネルの表示・操作に関する設定。設定画面（Phase 6）から変更可能にする前提のため、
// MVP の時点から View はこの構造体を経由してのみ挙動を決定する
// （[[docs-macos-snippet-menu-app-plan]] の設定駆動方針）。

import Foundation

/// 検索結果の並び順。
public enum SearchSortOrder: String, Codable, CaseIterable, Sendable {
    case relevance
    case usageCount
    case updatedAt
}

/// パネルの表示位置。
public enum PanelPosition: String, Codable, CaseIterable, Sendable {
    case mouseLocation
    case screenCenter
}

/// Enter キー押下時の既定アクション。
public enum EnterKeyBehavior: String, Codable, CaseIterable, Sendable {
    /// フォーカス中の入力欄へ挿入する（既定）。
    case insert
    /// クリップボードへコピーするだけで、挿入は行わない。
    case copyOnly
}

/// タグ一覧・ドリルダウン中のサブタグ候補の並び順。
public enum TagSortOrder: String, Codable, CaseIterable, Sendable {
    /// タグ登録順（`store.library.tags` の順序）。
    case registrationOrder
    /// 一致件数の多い順。
    case snippetCountDescending
}

/// パネルの表示・操作に関する設定。
public struct PanelPreferences: Equatable, Sendable {
    public var sectionOrder: [PanelSection]
    public var enabledSections: Set<PanelSection>
    public var recentsLimit: Int
    public var searchResultLimit: Int
    public var searchSortOrder: SearchSortOrder
    public var tagSortOrder: TagSortOrder
    public var presentationPosition: PanelPosition
    public var insertionStrategy: InsertionStrategy
    public var enterKeyBehavior: EnterKeyBehavior
    public var isNumberKeySelectionEnabled: Bool
    public var isTagColorShown: Bool
    public var clipboardRestoreDelayMs: Int
    public var fontSize: AppFontSize

    public init(
        sectionOrder: [PanelSection] = PanelSection.defaultOrder,
        enabledSections: Set<PanelSection> = Set(PanelSection.defaultOrder),
        recentsLimit: Int = 8,
        searchResultLimit: Int = 20,
        searchSortOrder: SearchSortOrder = .relevance,
        tagSortOrder: TagSortOrder = .registrationOrder,
        presentationPosition: PanelPosition = .mouseLocation,
        insertionStrategy: InsertionStrategy = .automatic,
        enterKeyBehavior: EnterKeyBehavior = .insert,
        isNumberKeySelectionEnabled: Bool = true,
        isTagColorShown: Bool = true,
        clipboardRestoreDelayMs: Int = ClipboardInserter.defaultRestoreDelayMs,
        fontSize: AppFontSize = .medium
    ) {
        self.sectionOrder = sectionOrder
        self.enabledSections = enabledSections
        self.recentsLimit = recentsLimit
        self.searchResultLimit = searchResultLimit
        self.searchSortOrder = searchSortOrder
        self.tagSortOrder = tagSortOrder
        self.presentationPosition = presentationPosition
        self.insertionStrategy = insertionStrategy
        self.enterKeyBehavior = enterKeyBehavior
        self.isNumberKeySelectionEnabled = isNumberKeySelectionEnabled
        self.isTagColorShown = isTagColorShown
        self.clipboardRestoreDelayMs = clipboardRestoreDelayMs
        self.fontSize = fontSize
    }

    /// 既定値のみのプリファレンス（設定 UI 実装前の MVP 段階で使用）。
    public static let `default` = PanelPreferences()

    /// 表示対象のセクションを、設定された表示順のまま返す。
    public var orderedEnabledSections: [PanelSection] {
        sectionOrder.filter { enabledSections.contains($0) }
    }
}
