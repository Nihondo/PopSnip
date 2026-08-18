// MARK: - KeyEventSender.swift
// CGEvent によるキーストローク合成を担当する。
// ClipboardInserter（Cmd+V・左矢印）と SelectionClipboardReader（Cmd+C）が共有する。

import AppKit
import Foundation

/// CGEvent によるキーストローク合成を担当する（PopSnipCore 内部専用）。
enum KeyEventSender {
    /// Cmd + `virtualKey` を送出する。
    /// イベントへ `.maskCommand` を明示的に設定するため、ショートカットの他修飾キーが
    /// 物理的に押されたまま残っていても Cmd+<key> として配送される。
    static func postCommandKeyCombo(virtualKey: CGKeyCode) {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let commandKeyCode: CGKeyCode = 0x37 // kVK_Command

        let commandDown = CGEvent(keyboardEventSource: eventSource, virtualKey: commandKeyCode, keyDown: true)
        let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: false)
        keyUp?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: eventSource, virtualKey: commandKeyCode, keyDown: false)

        commandDown?.post(tap: .cghidEventTap)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }

    /// 左矢印キーを `count` 回送出する（キャレット戻し用）。
    static func postLeftArrow(count: Int) {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let leftArrowKeyCode: CGKeyCode = 0x7B // kVK_LeftArrow

        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: leftArrowKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: leftArrowKeyCode, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
