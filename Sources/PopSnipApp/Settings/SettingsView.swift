// MARK: - SettingsView.swift
// 設定画面: フローティングサイドバー方式のタブ切り替え。
// timeSlice/Sources/timeSliceApp/SettingsView.swift の構成を移植し、
// PopSnip の設定タブ（一般 / パネル表示 / ショートカット / 権限 / アップデート）に当てはめる
// （UI_fix.md「タブ切り替えではなく、フローティングサイドバー方式にする」）。

import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: Hashable, CaseIterable {
        case general
        case panel
        case shortcut
        case permission
        case update

        var localizationKey: String {
            switch self {
            case .general:
                return "settings.tab.general"
            case .panel:
                return "settings.tab.panel"
            case .shortcut:
                return "settings.tab.shortcut"
            case .permission:
                return "settings.tab.permission"
            case .update:
                return "settings.tab.update"
            }
        }

        var systemImage: String {
            switch self {
            case .general:
                return "gearshape"
            case .panel:
                return "rectangle.on.rectangle"
            case .shortcut:
                return "keyboard"
            case .permission:
                return "lock.shield"
            case .update:
                return "arrow.down.circle"
            }
        }
    }

    @ObservedObject var store: SnippetStore
    let shortcutService: GlobalShortcutService

    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(L10n.string(tab.localizationKey), systemImage: tab.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailView
        }
        .toolbar(removing: .sidebarToggle)
        .frame(
            minWidth: DesignTokens.WindowSize.settingsMinWidth,
            idealWidth: 780,
            minHeight: DesignTokens.WindowSize.settingsMinHeight,
            idealHeight: 560
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .general, .none:
            GeneralSettingsView(store: store)
        case .panel:
            PanelLayoutSettingsView()
        case .shortcut:
            ShortcutSettingsView(shortcutService: shortcutService)
        case .permission:
            PermissionView()
        case .update:
            UpdateSettingsView()
        }
    }
}
