// MARK: - SnippetListWindowController.swift
// 一覧編集ウインドウの表示を管理する。

import AppKit
import SwiftUI

@MainActor
final class SnippetListWindowController: NSWindowController {
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("snippetList")

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
        newWindow.center()
        return newWindow
    }
}
