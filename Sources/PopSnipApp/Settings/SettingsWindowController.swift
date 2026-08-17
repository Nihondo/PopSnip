// MARK: - SettingsWindowController.swift
// 設定ウインドウを必要時にだけ生成・表示する AppKit コントローラー。
// AgentLimits/AgentLimits/App/SettingsWindowController.swift の構成パターンを移植。

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("settings")
    private static let frameAutosaveName = "PopSnip.SettingsWindow"

    private let store: SnippetStore
    private let shortcutService: GlobalShortcutService

    init(store: SnippetStore, shortcutService: GlobalShortcutService) {
        self.store = store
        self.shortcutService = shortcutService
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showSettingsWindow() {
        if window == nil {
            window = makeSettingsWindow()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let rootView = SettingsView(store: store, shortcutService: shortcutService)
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.string("window.settings.title")
        newWindow.identifier = Self.settingsWindowIdentifier
        newWindow.styleMask = [.titled, .closable, .resizable]
        newWindow.minSize = NSSize(
            width: DesignTokens.WindowSize.settingsMinWidth,
            height: DesignTokens.WindowSize.settingsMinHeight
        )
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
