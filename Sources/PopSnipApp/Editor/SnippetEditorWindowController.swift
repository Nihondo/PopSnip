// MARK: - SnippetEditorWindowController.swift
// スニペット登録・編集ウインドウの表示を管理する。呼び出しごとに内容（新規 or 編集対象、
// 選択範囲からの自動投入テキスト）が変わるため、ウインドウ自体は使い回しつつ rootView を
// 差し替える。

import AppKit
import SwiftUI

@MainActor
final class SnippetEditorWindowController: NSWindowController {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("snippetEditor")

    private let store: SnippetStore

    init(store: SnippetStore) {
        self.store = store
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 編集画面を表示する。`editingSnippetID` が nil の場合は新規登録として開く。
    func showEditor(editingSnippetID: UUID?, initialBody: String) {
        let rootView = SnippetEditorView(
            store: store,
            editingSnippetID: editingSnippetID,
            initialBody: initialBody,
            onFinish: { [weak self] in
                self?.window?.close()
            }
        )

        if let window {
            (window.contentViewController as? NSHostingController<SnippetEditorView>)?.rootView = rootView
        } else {
            window = makeWindow(rootView: rootView)
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(rootView: SnippetEditorView) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.string("window.editor.title")
        newWindow.identifier = Self.windowIdentifier
        newWindow.styleMask = [.titled, .closable]
        newWindow.isReleasedWhenClosed = false
        newWindow.isRestorable = false
        newWindow.center()
        return newWindow
    }
}
