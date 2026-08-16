// MARK: - PanelSection.swift
// パネル内のセクション種別。並び替え・表示ON/OFF の対象単位。
// パネル UI はこの CaseIterable を `sectionOrder` の順に ForEach で描画し、
// セクション構成をベタ書きしない（[[docs-macos-snippet-menu-app-plan]] の設定駆動方針）。

import Foundation

/// パネル内で表示されるセクション。
public enum PanelSection: String, Codable, CaseIterable, Identifiable, Sendable {
    /// お気に入り（v0.2）。
    case favorites
    /// タグ一覧。
    case tags
    /// 最近使用したスニペット。
    case recents
    /// すべてのスニペット。
    case allSnippets

    public var id: String { rawValue }

    /// MVP で有効化される既定のセクション構成・順序。
    public static let defaultOrder: [PanelSection] = [.tags, .recents, .allSnippets]

    public var localizationKey: String {
        switch self {
        case .favorites:
            return "panel.section.favorites"
        case .tags:
            return "panel.section.tags"
        case .recents:
            return "panel.section.recents"
        case .allSnippets:
            return "panel.section.allSnippets"
        }
    }
}
