// MARK: - SnippetBodyTextView.swift
// スニペット本文編集欄。macOS 14 ターゲットのため SwiftUI の
// `TextEditor(text:selection:)`（macOS 26+）は使えず、プレースホルダのクリック挿入には
// カーソル位置の直接操作が必要なため、NSTextView を SwiftUI へラップする。
// 構造は IMESafeSearchField.swift（Coordinator + onXxxCreated で AppKit インスタンスを
// 呼び出し元へ渡すパターン）を踏襲する。
//
// ドラッグ&ドロップでのプレースホルダ挿入は、NSTextView（isEditable かつ
// isRichText = false）が標準で持つテキストドロップ挙動に任せる。標準実装はマウス追従の
// 挿入キャレット表示を内蔵しているため、performDragOperation を自前実装しない。
// 初回ドラッグ時だけは本文欄が first responder になっておらず標準ドロップが無視されるため、
// draggingEntered で先に本文欄を有効化してから必ず super へ委譲する。

import AppKit
import SwiftUI

struct SnippetBodyTextView: NSViewRepresentable {
    @Binding var text: String
    /// 生成された NSTextView を呼び出し元（SnippetEditorView）へ渡す。
    /// パレットからのクリック挿入時にカーソル位置へ差し込むために使う。
    var onTextViewCreated: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DragReadyTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.drawsBackground = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.applyHighlight(to: textView)
        // makeNSView の更新トランザクション中に呼び出し元の @State を変更しない。
        DispatchQueue.main.async {
            onTextViewCreated(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        // IME の未確定文字列へ外部値を書き戻さない。
        guard textView.hasMarkedText() == false else {
            return
        }
        guard textView.string != text else {
            return
        }
        textView.string = text
        context.coordinator.applyHighlight(to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SnippetBodyTextView

        init(_ parent: SnippetBodyTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            parent.text = textView.string
            applyHighlight(to: textView)
        }

        /// 本文中の `{{ }}` トークンを色分けする。
        /// IME 変換中（`hasMarkedText()`）に `textStorage` を触ると変換候補が壊れるため、
        /// その間はハイライト適用をスキップする
        /// （SnippetPanelPresenter が同じ理由で hasMarkedText を見ているのと同じ配慮）。
        func applyHighlight(to textView: NSTextView) {
            guard textView.hasMarkedText() == false, let textStorage = textView.textStorage else {
                return
            }
            let text = textView.string
            let occurrences = PlaceholderParser.scan(text)
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)

            textStorage.beginEditing()
            textStorage.removeAttribute(.backgroundColor, range: fullRange)
            textStorage.removeAttribute(.foregroundColor, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

            for occurrence in occurrences where occurrence.isEscaped == false {
                let nsRange = NSRange(occurrence.range, in: text)
                if occurrence.isKnown {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: nsRange)
                    textStorage.addAttribute(
                        .backgroundColor,
                        value: NSColor.controlAccentColor.withAlphaComponent(0.12),
                        range: nsRange
                    )
                } else {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: nsRange)
                    textStorage.addAttribute(
                        .backgroundColor,
                        value: NSColor.systemRed.withAlphaComponent(0.12),
                        range: nsRange
                    )
                }
            }
            textStorage.endEditing()
        }
    }
}

/// 初回ドラッグで本文欄を編集対象にしてから、NSTextView 標準のドロップ処理へ委譲する。
private final class DragReadyTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }
        updateDragTypeRegistration()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        window?.makeFirstResponder(self)
        return super.draggingEntered(sender)
    }
}
