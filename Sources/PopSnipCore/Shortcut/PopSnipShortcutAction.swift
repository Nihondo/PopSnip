// MARK: - PopSnipShortcutAction.swift
// ホットキーを割り当て可能なアクション。設定画面はこの CaseIterable を列挙するだけでよい。
// アクションを増やすときは case を足すだけで済むようにするための設計（[[docs-macos-snippet-menu-app-plan]] 参照）。

import Foundation

/// グローバルショートカットを割り当てられるアクションの種類。
/// 宣言されたケースは全て有効（`AppSharedState.wireHandlers()` にハンドラが必ず紐づく）。
/// ケースを足すときはハンドラの配線も忘れずに行うこと。
public enum PopSnipShortcutAction: String, CaseIterable, Sendable, Codable {
    /// 検索パネルを表示する。
    case showPanel
    /// 選択範囲から即座にスニペット登録画面を開く（検索パネルは経由しない）。
    case quickRegister
    /// 一覧編集ウインドウを開く。
    case showList

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
