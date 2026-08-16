// MARK: - SettingsTabView.swift
// 設定画面のタブ構成: 一般 / パネル表示 / ショートカット / スニペット / 権限。

import SwiftUI

struct SettingsTabView: View {
    @ObservedObject var store: SnippetStore
    let shortcutService: GlobalShortcutService

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem { Label(L10n.string("settings.tab.general"), systemImage: "gearshape") }

            PanelLayoutSettingsView()
                .tabItem { Label(L10n.string("settings.tab.panel"), systemImage: "rectangle.on.rectangle") }

            ShortcutSettingsView(shortcutService: shortcutService)
                .tabItem { Label(L10n.string("settings.tab.shortcut"), systemImage: "keyboard") }

            PermissionView()
                .tabItem { Label(L10n.string("settings.tab.permission"), systemImage: "lock.shield") }
        }
        .frame(
            minWidth: DesignTokens.WindowSize.settingsMinWidth,
            minHeight: DesignTokens.WindowSize.settingsMinHeight
        )
    }
}
