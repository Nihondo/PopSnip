// MARK: - AppSharedState.swift
// アプリ全体の共有状態。ストア・ショートカット・パネル・メニューバー・各ウインドウの
// コントローラーを生成し、相互のハンドラを配線する。

import AppKit
import OSLog

@MainActor
final class AppSharedState: NSObject {
    let store: SnippetStore
    let shortcutService: GlobalShortcutService
    let panelPresenter: SnippetPanelPresenter
    let statusBarController: StatusBarController

    private let settingsWindowController: SettingsWindowController
    private let editorWindowController: SnippetEditorWindowController
    private let listWindowController: SnippetListWindowController

    override init() {
        let store = SnippetStore()
        self.store = store
        self.shortcutService = GlobalShortcutService()
        self.panelPresenter = SnippetPanelPresenter(store: store)
        self.statusBarController = StatusBarController()
        self.settingsWindowController = SettingsWindowController(store: store, shortcutService: shortcutService)
        self.editorWindowController = SnippetEditorWindowController(store: store)
        self.listWindowController = SnippetListWindowController(store: store)
        super.init()

        wireHandlers()
        registerShortcuts()
        logAccessibilityPermissionStateIfNeeded()
    }

    private func wireHandlers() {
        shortcutService.handlers[.showPanel] = { [weak self] in
            self?.panelPresenter.toggle()
        }

        panelPresenter.onOpenEditor = { [weak self] target in
            self?.editorWindowController.showEditor(
                editingSnippetID: nil,
                initialBody: target?.selectedText ?? ""
            )
        }
        panelPresenter.onOpenList = { [weak self] in
            self?.listWindowController.showList()
        }
        panelPresenter.onOpenSettings = { [weak self] in
            self?.settingsWindowController.showSettingsWindow()
        }

        statusBarController.onShowPanel = { [weak self] in
            self?.panelPresenter.present()
        }
        statusBarController.onOpenList = { [weak self] in
            self?.listWindowController.showList()
        }
        statusBarController.onOpenSettings = { [weak self] in
            self?.settingsWindowController.showSettingsWindow()
        }
        statusBarController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func registerShortcuts() {
        for action in PopSnipShortcutAction.activeInMVP {
            let configuration = AppSettingsResolver.resolveShortcutConfiguration(for: action)
            shortcutService.register(action, configuration: configuration)
        }
    }

    private func logAccessibilityPermissionStateIfNeeded() {
        guard AccessibilityPermission.isGranted() == false else {
            return
        }
        Logger.app.notice("Accessibility 権限が未許可です。設定画面から許可してください。")
    }
}
