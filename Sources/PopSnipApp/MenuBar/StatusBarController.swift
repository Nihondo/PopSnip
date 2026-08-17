// MARK: - StatusBarController.swift
// NSStatusItem を管理するメニューバーコントローラー。
// AgentLimits/AgentLimits/App/MenuBar/MenuBarController.swift の構成パターンを参考にした
// 簡易版（PopSnip は常駐アイコンのみで、ダッシュボード表示は持たない）。
// UI_fix.md「メニューバーの各メニューのアイコンを、SF Symbolアイコンから選定する」
// 「メニューバー項目は...」の並びに合わせて再構成している。

import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem

    var onShowPanel: (() -> Void)?
    var onOpenList: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onShowAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        refreshMenu()
        observeShortcutChanges()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        button.image = NSImage(
            systemSymbolName: "text.badge.plus",
            accessibilityDescription: "PopSnip"
        )
    }

    /// StatusBarController はアプリ生存期間を通じて保持され続けるため、
    /// 観測トークンの明示的な解除（removeObserver）は行わない
    /// （他のコントローラーと同様、プロセス終了までの寿命を前提にしている）。
    private func observeShortcutChanges() {
        NotificationCenter.default.addObserver(
            forName: .popSnipShortcutsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMenu()
        }
    }

    /// メニュー項目を作り直す。ショートカット設定が変わったときにも呼ばれる。
    func refreshMenu() {
        let menu = NSMenu()

        menu.addItem(makeItem(
                titleKey: "menu.openSettings",
                symbolName: "gearshape",
                action: #selector(handleOpenSettings)
        ))
        menu.addItem(.separator())
        menu.addItem(makeShortcutItem(
            titleKey: "menu.showPanel",
            symbolName: "magnifyingglass",
            action: #selector(handleShowPanel),
            shortcutAction: .showPanel
        ))
        menu.addItem(makeShortcutItem(
            titleKey: "menu.openList",
            symbolName: "list.bullet.rectangle",
            action: #selector(handleOpenList),
            shortcutAction: .showList
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            titleKey: "menu.checkForUpdates",
            symbolName: "arrow.down.circle",
            action: #selector(handleCheckForUpdates)
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            titleKey: "menu.about",
            symbolName: "info.circle",
            action: #selector(handleShowAbout)
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            titleKey: "menu.quit",
            symbolName: "xmark.circle",
            action: #selector(handleQuit)
        ))

        statusItem.menu = menu
    }

    private func makeItem(titleKey: String, symbolName: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: L10n.string(titleKey), action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        return item
    }

    /// ショートカットが設定されているアクションに紐づくメニュー項目。設定されたキーを
    /// `keyEquivalent` に反映し、右端にショートカット表示が出るようにする。
    private func makeShortcutItem(
        titleKey: String,
        symbolName: String,
        action: Selector,
        shortcutAction: PopSnipShortcutAction
    ) -> NSMenuItem {
        let item = makeItem(titleKey: titleKey, symbolName: symbolName, action: action)
        guard let configuration = AppSettingsResolver.resolveShortcutConfiguration(for: shortcutAction) else {
            return item
        }
        item.keyEquivalent = configuration.menuKeyEquivalent
        item.keyEquivalentModifierMask = configuration.menuKeyEquivalentModifierMask
        return item
    }

    @objc private func handleShowPanel() {
        onShowPanel?()
    }

    @objc private func handleOpenList() {
        onOpenList?()
    }

    @objc private func handleCheckForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings?()
    }

    @objc private func handleShowAbout() {
        onShowAbout?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
