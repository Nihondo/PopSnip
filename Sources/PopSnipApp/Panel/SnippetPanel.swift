// MARK: - SnippetPanel.swift
// 検索パネル本体の NSPanel サブクラス。
// timeSlice の ManualCaptureCommentPanel と異なる最大の点は styleMask に
// `.nonactivatingPanel` を含めること。これにより、パネルがキーウインドウになって
// 検索ボックスがキー入力を受け取れる一方で、`NSApp.activate` を呼ばない限り
// 前面アプリ（フォーカスを持っていたアプリ）が非アクティブ化されない
// （[[docs-macos-snippet-menu-app-plan]] の「挿入経路」設計を参照）。

import AppKit

/// 検索パネルのウインドウ。`.nonactivatingPanel` によりフォーカスを奪わずにキー入力を受け取る。
final class SnippetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
