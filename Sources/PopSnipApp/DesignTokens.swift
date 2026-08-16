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
        static let settingsMinWidth: CGFloat = 640
        static let settingsMinHeight: CGFloat = 480
        static let panelWidth: CGFloat = 480
    }
}
