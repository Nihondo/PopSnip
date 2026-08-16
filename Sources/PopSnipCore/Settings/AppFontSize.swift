// MARK: - AppFontSize.swift
// パネル・スニペット一覧で使う文字サイズの3段階設定。
// DesignTokens.Typography のベースサイズに scale を掛けて使う。

import CoreGraphics

/// 表示文字サイズの3段階。
public enum AppFontSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    /// ベースサイズに掛ける倍率。
    public var scale: CGFloat {
        switch self {
        case .small:
            return 0.88
        case .medium:
            return 1.0
        case .large:
            return 1.18
        }
    }

    /// 設定画面で表示するローカライズキー。
    public var localizationKey: String {
        "settings.general.fontSize.\(rawValue)"
    }
}
