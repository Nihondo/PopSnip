// MARK: - PanelKeyBinding.swift
// パネル上のキー操作をテーブル化する。SnippetPanelView の onKeyPress はこのテーブルを
// 引くだけにし、キー割り当てをベタ書きしない
// （[[docs-macos-snippet-menu-app-plan]] の設定駆動方針。MVP では既定値固定だが、
// テーブル経由で引く形にしておくことで将来の設定 UI 追加時に View 側の変更が不要になる）。

import Foundation

/// パネル上で発生しうるキー入力を抽象化した型。View 層が SwiftUI の KeyPress からこれへ変換する。
public enum PanelKeyEvent: Equatable, Sendable {
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case tabForward
    case tabBackward
    case confirm
    case cancel
    /// 1〜9 の数字キー（⌘1〜⌘9 の直接選択用）。
    case digit(Int)
}

/// キー入力の結果として実行すべきアクション。
public enum PanelKeyAction: Equatable, Sendable {
    case moveSelectionUp
    case moveSelectionDown
    case moveTagSelectionPrevious
    case moveTagSelectionNext
    case confirmSelection
    case cancel
    /// 0-based のインデックスを直接選択する。
    case selectByIndex(Int)
}

/// `PanelKeyEvent` を `PanelKeyAction` へ解決するテーブル。
public enum PanelKeyBinding {
    public static func resolveAction(
        for event: PanelKeyEvent,
        preferences: PanelPreferences
    ) -> PanelKeyAction? {
        switch event {
        case .arrowUp:
            return .moveSelectionUp
        case .arrowDown:
            return .moveSelectionDown
        case .arrowLeft, .tabBackward:
            return .moveTagSelectionPrevious
        case .arrowRight, .tabForward:
            return .moveTagSelectionNext
        case .confirm:
            return .confirmSelection
        case .cancel:
            return .cancel
        case .digit(let digit):
            guard preferences.isNumberKeySelectionEnabled, (1...9).contains(digit) else {
                return nil
            }
            return .selectByIndex(digit - 1)
        }
    }
}
