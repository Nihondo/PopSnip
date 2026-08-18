// MARK: - PasteboardSnapshot.swift
// クリップボードの内容を型ごと複製したスナップショット。
// ClipboardInserter（Cmd+V）と SelectionClipboardReader（Cmd+C）の双方から、
// 「ユーザーのクリップボードを壊さない」ための退避・復元ロジックとして共有する。

import AppKit
import Foundation

/// クリップボードの内容を型ごと複製したスナップショット。
struct PasteboardSnapshot {
    /// 各アイテムが持つ (型, データ) の一覧。
    let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]
    /// 退避直前の changeCount。復元直前にこの値からの変化を確認するために使う。
    let changeCountBeforeCapture: Int

    /// `pasteboard` の現在の内容を退避する。
    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
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

    /// 退避した内容を `pasteboard` へ復元する。
    /// 退避後に自分が書き込んでいなければ（changeCount が不変なら）何もしない。
    func restore(to pasteboard: NSPasteboard) {
        // 復元直前に、まだ自分が書き込んだ内容のままかを確認する。
        // その間にユーザーが別の内容を手動コピーしていた場合は、それを上書きしない。
        guard pasteboard.changeCount != changeCountBeforeCapture else {
            return
        }

        pasteboard.clearContents()
        guard items.isEmpty == false else {
            // 退避時点でクリップボードが空だった場合は、空のまま維持する。
            return
        }

        let restoredItems: [NSPasteboardItem] = items.map { typedDataList in
            let item = NSPasteboardItem()
            for (type, data) in typedDataList {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
