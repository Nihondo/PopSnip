// MARK: - ClipboardInserter.swift
// クリップボード + Cmd+V による挿入（挿入方式 B・フォールバック）。
// ユーザーのクリップボードを壊さないことを絶対条件とし、全 NSPasteboardItem の全型を
// 退避してから貼り付け、貼り付け後に復元する。

import AppKit
import Foundation

/// クリップボード経由の貼り付け（Cmd+V）による挿入を担当する。
public enum ClipboardInserter {
    /// 貼り付け完了待機のデフォルト時間（ミリ秒）。Electron 系アプリ（Slack / VS Code）は反映が遅いため
    /// 設定で調整可能にする前提だが、MVP では固定値を使う。
    public static let defaultRestoreDelayMs = 120
    /// 待機時間の上限（ミリ秒）。
    public static let maxRestoreDelayMs = 300

    /// キャレット移動（左矢印キー送出）の暴走防止用上限。
    private static let maxCaretMoveCount = 500

    /// `text` をクリップボード経由で貼り付ける。
    /// 貼り付けの成否によらず、必ず元のクリップボード内容を復元する（`defer` で保証）。
    /// - Parameter caretCharacterOffsetFromEnd: `{{cursor}}` プレースホルダが指定していた
    ///   キャレット位置（貼り付けたテキストの末尾から何文字戻るか）。貼り付け完了を待った後、
    ///   左矢印キーをその回数だけ送出する。この経路はアプリ側のカーソル移動 API を持たないため
    ///   キー送出でしか実現できず、貼り付け先アプリの反映タイミング次第では確実性が下がる。
    public static func insert(
        _ text: String,
        restoreDelayMs: Int = ClipboardInserter.defaultRestoreDelayMs,
        caretCharacterOffsetFromEnd: Int? = nil
    ) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        defer {
            snapshot.restore(to: pasteboard)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let ownChangeCountAfterWrite = pasteboard.changeCount
        KeyEventSender.postCommandKeyCombo(virtualKey: 0x09) // kVK_ANSI_V

        // 貼り付け完了を待つ。changeCount の変化（ペースト先アプリがクリップボードを読み取った
        // ことの直接的なシグナルにはならないが、少なくとも自分の書き込みが安定して存在する時間を
        // 確保する）を見つつ、上限までポーリングする。
        waitForPasteToSettle(
            pasteboard: pasteboard,
            expectedChangeCount: ownChangeCountAfterWrite,
            delayMs: min(restoreDelayMs, ClipboardInserter.maxRestoreDelayMs)
        )

        moveCaretLeftIfNeeded(by: caretCharacterOffsetFromEnd)
    }

    // MARK: - 貼り付け

    /// 貼り付け直後に左矢印キーを `characterCount` 回送出してキャレットを戻す。
    private static func moveCaretLeftIfNeeded(by characterCount: Int?) {
        guard let characterCount, characterCount > 0, characterCount <= maxCaretMoveCount else {
            return
        }
        KeyEventSender.postLeftArrow(count: characterCount)
    }

    private static func waitForPasteToSettle(
        pasteboard: NSPasteboard,
        expectedChangeCount: Int,
        delayMs: Int
    ) {
        // 固定 sleep ではなく、貼り付け先アプリがクリップボードへ触れて changeCount が動くのを
        // 短い間隔でポーリングする。動かなければ delayMs 経過で打ち切る。
        let pollIntervalMs = 10
        var elapsedMs = 0
        while elapsedMs < delayMs {
            Thread.sleep(forTimeInterval: TimeInterval(pollIntervalMs) / 1000)
            elapsedMs += pollIntervalMs
            if pasteboard.changeCount != expectedChangeCount {
                break
            }
        }
    }
}
