// MARK: - IMESafeSearchField.swift
// 日本語入力（IME）に安全な検索フィールド。
//
// 当初は NSTextFieldDelegate.control(_:textView:doCommandBy:) で上下矢印キー / Enter /
// Backspace を判定していたが、単一行の NSTextField では field editor が上下矢印キーに対して
// doCommandBy を確実に発火させないケースがあり、検索結果の絞り込み中やタグドリルダウン中に
// カーソルキーでの選択移動ができない不具合が残った。
//
// そのため、このフィールド自体はテキストバインディングのみを担当し、キー操作の判定は
// SnippetPanelPresenter 側の NSEvent ローカルモニタへ一本化する。そちらで
// `hasMarkedText`（IME 変換中かどうか）を見て、変換中は素通しし、変換中でなければ
// アプリ側のキー操作として処理する。

import AppKit
import SwiftUI

struct IMESafeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    /// 生成された NSTextField を呼び出し元（SnippetPanelPresenter）へ渡す。
    /// IME 変換中判定（hasMarkedText）とキーモニタでのフォーカス確認に使う。
    var onFieldCreated: (NSTextField) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: fontSize)
        textField.lineBreakMode = .byClipping
        textField.stringValue = text
        textField.delegate = context.coordinator

        onFieldCreated(textField)

        // パネル表示直後に自動でファーストレスポンダにする。
        // makeNSView 実行時点ではまだウインドウに未接続のことがあるため、次のランループで行う。
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IMESafeSearchField

        init(_ parent: IMESafeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }
            parent.text = textField.stringValue
        }
    }
}
