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
        // Sparkle の updater を起動時から動かしておく（自動チェックの間隔を UserDefaults 通りに保つため）。
        _ = AppUpdateController.shared
    }

    private func wireHandlers() {
        shortcutService.handlers[.showPanel] = { [weak self] in
            self?.panelPresenter.toggle()
        }
        shortcutService.handlers[.showList] = { [weak self] in
            self?.listWindowController.showList()
        }
        shortcutService.handlers[.quickRegister] = { [weak self] in
            self?.handleQuickRegisterShortcut()
        }

        panelPresenter.onOpenEditor = { [weak self] editingSnippetID, target in
            self?.editorWindowController.showEditor(
                editingSnippetID: editingSnippetID,
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
        statusBarController.onCheckForUpdates = {
            AppUpdateController.shared.checkForUpdates()
        }
        statusBarController.onShowAbout = {
            Self.showAboutPanel()
        }
        statusBarController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    /// macOS 標準の About パネルを表示する（UI_fix.md「About画面を新規作成」への対応。
    /// timeSlice と同じく独自ウインドウは作らず標準パネルを使う）。
    private static func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutPanelCredits])
    }

    private static var aboutPanelCredits: NSAttributedString {
        let githubURLString = "https://github.com/Nihondo/PopSnip"
        let creditsText = """
        Copyright © 2026 Nihondo
        GitHub: \(githubURLString)
        """
        let attributedCredits = NSMutableAttributedString(string: creditsText)
        let githubURLRange = (creditsText as NSString).range(of: githubURLString)
        if
            githubURLRange.location != NSNotFound,
            let githubURL = URL(string: githubURLString)
        {
            attributedCredits.addAttributes(
                [
                    .link: githubURL,
                    .foregroundColor: NSColor.linkColor
                ],
                range: githubURLRange
            )
        }
        return attributedCredits
    }

    private func registerShortcuts() {
        for action in PopSnipShortcutAction.allCases {
            let configuration = AppSettingsResolver.resolveShortcutConfiguration(for: action)
            shortcutService.register(action, configuration: configuration)
        }
    }

    /// 選択範囲から即座にスニペット登録画面を開く（検索パネルは経由しない）。
    private func handleQuickRegisterShortcut() {
        guard AccessibilityPermission.isGranted() else {
            AccessibilityPermission.requestIfNeeded()
            return
        }
        let target = FocusSnapshotResolver.resolveCurrentTarget()
        editorWindowController.showEditor(editingSnippetID: nil, initialBody: target?.selectedText ?? "")
    }

    private func logAccessibilityPermissionStateIfNeeded() {
        guard AccessibilityPermission.isGranted() == false else {
            return
        }
        Logger.app.notice("Accessibility 権限が未許可です。設定画面から許可してください。")
    }
}
