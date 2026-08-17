// MARK: - UserDefaultsKeys.swift
// UserDefaults のキー文字列をこのファイルへ集約する（AgentLimits と同方式）。
// View から UserDefaults のキー文字列を直接触らせず、必ずここを経由させる。

import Foundation

/// UserDefaults キーの一覧。
public enum UserDefaultsKeys {
    // MARK: - ショートカット（アクション単位）

    public static func shortcutKey(_ action: PopSnipShortcutAction) -> String {
        "shortcut.\(action.rawValue).key"
    }

    public static func shortcutModifiers(_ action: PopSnipShortcutAction) -> String {
        "shortcut.\(action.rawValue).modifiers"
    }

    public static func shortcutKeyCode(_ action: PopSnipShortcutAction) -> String {
        "shortcut.\(action.rawValue).keyCode"
    }

    // MARK: - 一般設定

    public static let launchAtLoginEnabled = "general.launchAtLoginEnabled"
    public static let insertionStrategy = "general.insertionStrategy"
    public static let clipboardRestoreDelayMs = "general.clipboardRestoreDelayMs"

    // MARK: - パネル表示設定

    public static let panelSectionOrder = "panel.sectionOrder"
    public static let panelEnabledSections = "panel.enabledSections"
    public static let panelRecentsLimit = "panel.recentsLimit"
    public static let panelSearchResultLimit = "panel.searchResultLimit"
    public static let panelSearchSortOrder = "panel.searchSortOrder"
    public static let panelTagSortOrder = "panel.tagSortOrder"
    public static let panelTagLayoutStyle = "panel.tagLayoutStyle"
    public static let panelPresentationPosition = "panel.presentationPosition"
    public static let panelEnterKeyBehavior = "panel.enterKeyBehavior"
    public static let panelIsNumberKeySelectionEnabled = "panel.isNumberKeySelectionEnabled"
    public static let panelIsTagColorShown = "panel.isTagColorShown"
    public static let panelFontSize = "panel.fontSize"
    public static let panelWindowWidth = "panel.windowWidth"
    public static let panelWindowHeight = "panel.windowHeight"

    // MARK: - スニペットストレージ

    public static let snippetFilePath = "storage.snippetFilePath"

    // MARK: - 編集画面

    /// プレースホルダガイダンスパレットの開閉状態（純粋な UI 表示状態のため
    /// AppSettingsResolver を経由せず @AppStorage で直接読み書きする）。
    public static let placeholderPaletteExpanded = "editor.placeholderPaletteExpanded"
}
