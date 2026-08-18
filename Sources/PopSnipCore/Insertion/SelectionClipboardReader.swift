// MARK: - SelectionClipboardReader.swift
// Cmd+C 送出とクリップボード退避・復元による選択テキスト読取。
// AXManualAccessibility（FocusSnapshotResolver の `SelectionRecoveryBudget`）でも選択テキストが
// 取れなかった場合の最終フォールバックとして「クイック登録」機能専用に使う。パネル表示のたびに
// Cmd+C が走ると、VS Code のように未選択時に現在行をコピーするアプリで意図しない挿入が起きたり、
// 表示が遅延したりするため、パネル経路（{{selection}} プレースホルダ）には適用しない。

import AppKit
import Foundation

/// Cmd+C 送出とクリップボード退避・復元による選択テキスト読取を担当する
/// （クイック登録専用フォールバック）。
/// ユーザーのクリップボードを壊さないことを絶対条件とし、読取の成否によらず
/// 必ず元のクリップボード内容を復元する。
@MainActor
public enum SelectionClipboardReader {
    /// コピー反映待ちの上限（ミリ秒）。
    public static let defaultTimeoutMs = 300

    /// 前面アプリへ Cmd+C を送出し、クリップボード経由で選択テキストを読み取る。
    /// changeCount が変化しなかった場合（未選択・コピー不可）は空文字を返す。
    /// 読取の成否によらず元のクリップボード内容を復元する（`defer` で保証）。
    ///
    /// 対象アプリ自身がコピーを実行するため、クリップボード履歴アプリには
    /// 「選択テキスト」と「復元された元の内容」の 2 件が記録される制限がある。
    public static func readSelectedText(timeoutMs: Int = SelectionClipboardReader.defaultTimeoutMs) -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        defer {
            snapshot.restore(to: pasteboard)
        }

        KeyEventSender.postCommandKeyCombo(virtualKey: 0x08) // kVK_ANSI_C

        // 固定 sleep ではなく、対象アプリがコピーを反映して changeCount が動くのを
        // 短い間隔でポーリングする。動かなければ timeoutMs 経過で「未選択」として打ち切る。
        let pollIntervalMs = 10
        var elapsedMs = 0
        while pasteboard.changeCount == snapshot.changeCountBeforeCapture, elapsedMs < timeoutMs {
            Thread.sleep(forTimeInterval: TimeInterval(pollIntervalMs) / 1000)
            elapsedMs += pollIntervalMs
        }

        guard pasteboard.changeCount != snapshot.changeCountBeforeCapture else {
            return ""
        }
        return (pasteboard.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
