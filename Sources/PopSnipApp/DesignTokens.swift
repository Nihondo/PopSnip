// MARK: - DesignTokens.swift
// 共有デザイントークン。AgentLimits/AgentLimits/App/DesignTokens.swift を拡張して移植。

import CoreGraphics

/// レイアウト・サイズの共有デザイントークン。
enum DesignTokens {
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let sectionGap: CGFloat = 20
    }

    enum CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let panel: CGFloat = 16
    }

    enum WindowSize {
        static let settingsMinWidth: CGFloat = 680
        static let settingsMinHeight: CGFloat = 460
        static let panelWidth: CGFloat = 480
        static let panelDefaultHeight: CGFloat = 420
        static let panelMinWidth: CGFloat = 360
        static let panelMinHeight: CGFloat = 220
        static let listSidebarMinWidth: CGFloat = 260
        static let listSidebarIdealWidth: CGFloat = 300
        static let listSidebarMaxWidth: CGFloat = 420
        static let editorWidth: CGFloat = 480
        static let editorHeight: CGFloat = 500
    }

    /// パネル・スニペット一覧で使うベースの文字サイズ。
    /// `AppFontSize.scale` を掛けて実際の表示サイズにする。
    enum Typography {
        static let rowTitle: CGFloat = 13
        static let rowBody: CGFloat = 11
        static let sectionHeader: CGFloat = 11
        static let searchField: CGFloat = 16
        static let indexHint: CGFloat = 10
    }
}
