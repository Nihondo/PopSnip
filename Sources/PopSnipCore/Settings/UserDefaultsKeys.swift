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
    public static let panelPresentationPosition = "panel.presentationPosition"
    public static let panelEnterKeyBehavior = "panel.enterKeyBehavior"
    public static let panelIsNumberKeySelectionEnabled = "panel.isNumberKeySelectionEnabled"
    public static let panelIsTagColorShown = "panel.isTagColorShown"

    // MARK: - スニペットストレージ

    public static let snippetFilePath = "storage.snippetFilePath"
}
