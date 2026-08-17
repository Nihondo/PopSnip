// MARK: - SnippetListWindowController.swift
// 一覧編集ウインドウの表示を管理する。

import AppKit
import SwiftUI

@MainActor
final class SnippetListWindowController: NSWindowController {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("snippetList")
    private static let frameAutosaveName = "PopSnip.SnippetListWindow"

    private let store: SnippetStore

    init(store: SnippetStore) {
        self.store = store
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showList() {
        // 外部から snippets.json が編集されていた場合に反映する
        // （検索パネルの .onAppear と同じパターン。UI_fix.md 起点の監査で見つかった反映漏れの修正）。
        store.reloadIfNeeded()
        if window == nil {
            window = makeWindow()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let rootView = SnippetListWindowView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.string("window.list.title")
        newWindow.identifier = Self.windowIdentifier
        newWindow.styleMask = [.titled, .closable, .resizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.isRestorable = false
        // setFrameAutosaveName はリサイズ・移動のたびに frame を自動保存し、
        // 呼び出し時点で保存済みデータがあれば直ちに復元する（戻り値で判定可能）。
        let didRestoreFrame = newWindow.setFrameAutosaveName(Self.frameAutosaveName)
        if !didRestoreFrame {
            newWindow.center()
        }
        return newWindow
    }
}
