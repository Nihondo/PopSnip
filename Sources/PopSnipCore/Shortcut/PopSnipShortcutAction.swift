// MARK: - PopSnipShortcutAction.swift
// ホットキーを割り当て可能なアクション。設定画面はこの CaseIterable を列挙するだけでよい。
// アクションを増やすときは case を足すだけで済むようにするための設計（[[docs-macos-snippet-menu-app-plan]] 参照）。

import Foundation

/// グローバルショートカットを割り当てられるアクションの種類。
public enum PopSnipShortcutAction: String, CaseIterable, Sendable, Codable {
    /// 検索パネルを表示する。MVP で唯一有効化されるアクション。
    case showPanel
    /// 選択範囲から即座にスニペット登録パネルを開く（v0.2）。
    case quickRegister
    /// 一覧編集ウインドウを開く（v0.2）。
    case showList

    /// MVP でホットキー登録の対象となるアクション。
    public static var activeInMVP: [PopSnipShortcutAction] {
        [.showPanel]
    }

    /// 設定画面などで表示するローカライズキー。
    public var localizationKey: String {
        switch self {
        case .showPanel:
            return "shortcut.action.showPanel"
        case .quickRegister:
            return "shortcut.action.quickRegister"
        case .showList:
            return "shortcut.action.showList"
        }
    }
}
