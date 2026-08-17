// MARK: - ClipboardInserter.swift
// クリップボード + Cmd+V による挿入（挿入方式 B・フォールバック）。
// ユーザーのクリップボードを壊さないことを絶対条件とし、全 NSPasteboardItem の全型を
// 退避してから貼り付け、貼り付け後に復元する。

import AppKit
import Foundation

/// クリップボードの内容を型ごと複製したスナップショット。
private struct PasteboardSnapshot {
    /// 各アイテムが持つ (型, データ) の一覧。
    let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]
    /// 退避直前の changeCount。復元直前にこの値からの変化を確認するために使う。
    let changeCountBeforeCapture: Int
}

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
        let snapshot = captureSnapshot(from: pasteboard)

        defer {
            restore(snapshot, to: pasteboard)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let ownChangeCountAfterWrite = pasteboard.changeCount
        postCommandV()

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

    // MARK: - 退避

    private static func captureSnapshot(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [(NSPasteboard.PasteboardType, Data)] in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type, data)
            }
        }
        return PasteboardSnapshot(items: items, changeCountBeforeCapture: pasteboard.changeCount)
    }

    // MARK: - 貼り付け

    private static func postCommandV() {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let commandKeyCode: CGKeyCode = 0x37 // kVK_Command
        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V

        let commandDown = CGEvent(keyboardEventSource: eventSource, virtualKey: commandKeyCode, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: false)
        vUp?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: eventSource, virtualKey: commandKeyCode, keyDown: false)

        commandDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }

    /// 貼り付け直後に左矢印キーを `characterCount` 回送出してキャレットを戻す。
    /// `postCommandV()` と同じ `CGEventSource`/`.cghidEventTap` の作法を踏襲する。
    private static func moveCaretLeftIfNeeded(by characterCount: Int?) {
        guard let characterCount, characterCount > 0, characterCount <= maxCaretMoveCount else {
            return
        }
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let leftArrowKeyCode: CGKeyCode = 0x7B // kVK_LeftArrow

        for _ in 0..<characterCount {
            let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: leftArrowKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: leftArrowKeyCode, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
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

    // MARK: - 復元

    private static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        // 復元直前に、まだ自分が書き込んだ内容のままかを確認する。
        // その間にユーザーが別の内容を手動コピーしていた場合は、それを上書きしない。
        guard pasteboard.changeCount != snapshot.changeCountBeforeCapture else {
            // 自分の書き込みが一度も発生していない（=何もしていない）ケース。復元不要。
            return
        }

        pasteboard.clearContents()
        guard snapshot.items.isEmpty == false else {
            // 退避時点でクリップボードが空だった場合は、空のまま維持する。
            return
        }

        let restoredItems: [NSPasteboardItem] = snapshot.items.map { typedDataList in
            let item = NSPasteboardItem()
            for (type, data) in typedDataList {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
