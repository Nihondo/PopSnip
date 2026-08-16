// MARK: - ShortcutChangeNotification.swift
// 設定画面でショートカットが変更されたことをメニューバーへ知らせる通知。
// StatusBarController はこれを購読してメニュー項目のショートカット表示を更新する。

import Foundation

extension Notification.Name {
    public static let popSnipShortcutsDidChange = Notification.Name("com.dmng.popsnip.shortcutsDidChange")
}
