// MARK: - StatusBarController.swift
// NSStatusItem を管理するメニューバーコントローラー。
// AgentLimits/AgentLimits/App/MenuBar/MenuBarController.swift の構成パターンを参考にした
// 簡易版（PopSnip は常駐アイコンのみで、ダッシュボード表示は持たない）。

import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem

    var onShowPanel: (() -> Void)?
    var onOpenList: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        buildMenu()
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

    private func buildMenu() {
        let menu = NSMenu()

        menu.addItem(makeItem(titleKey: "menu.showPanel", action: #selector(handleShowPanel)))
        menu.addItem(.separator())
        menu.addItem(makeItem(titleKey: "menu.openList", action: #selector(handleOpenList)))
        menu.addItem(makeItem(titleKey: "menu.openSettings", action: #selector(handleOpenSettings)))
        menu.addItem(.separator())
        menu.addItem(makeItem(titleKey: "menu.quit", action: #selector(handleQuit)))

        statusItem.menu = menu
    }

    private func makeItem(titleKey: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: L10n.string(titleKey), action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func handleShowPanel() {
        onShowPanel?()
    }

    @objc private func handleOpenList() {
        onOpenList?()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
