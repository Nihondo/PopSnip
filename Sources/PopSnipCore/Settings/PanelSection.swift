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

    /// 既定のセクション構成・順序。新規インストール時はこの並びで表示される。
    /// 既存インストールでは `AppSettingsResolver.resolvePanelPreferences()` が、永続化済みの
    /// `sectionOrder` に無いケースをここから補って末尾へ追記する（新しいセクションを
    /// 追加したときに、保存済み設定を持つ環境でも自動的に選択肢へ現れるようにするため）。
    public static let defaultOrder: [PanelSection] = [.favorites, .tags, .recents, .allSnippets]

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
