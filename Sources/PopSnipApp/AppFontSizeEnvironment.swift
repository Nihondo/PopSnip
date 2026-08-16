// MARK: - AppFontSizeEnvironment.swift
// PanelPreferences.fontSize を SwiftUI の Environment 経由でパネル/一覧の各行へ伝える。
// present() のたびに設定を読み直すパネルと、開きっぱなしでも即時反映したい一覧の
// どちらでも `.environment(\.appFontSize, ...)` を root に注入するだけで済むようにする。

import SwiftUI

private struct AppFontSizeKey: EnvironmentKey {
    static let defaultValue: AppFontSize = .medium
}

extension EnvironmentValues {
    var appFontSize: AppFontSize {
        get { self[AppFontSizeKey.self] }
        set { self[AppFontSizeKey.self] = newValue }
    }
}

extension View {
    /// `base` に現在の `appFontSize` の倍率を掛けたフォントを適用する。
    func scaledFont(
        _ base: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(base: base, weight: weight, design: design))
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.appFontSize) private var appFontSize
    let base: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(appFontSize.font(base, weight: weight, design: design))
    }
}

extension AppFontSize {
    /// `SnippetRowView` のハイライト描画のように `Text` を直接連結する箇所では
    /// View 修飾子ではなく `Font` 値そのものが要るため、こちらを使う。
    func font(
        _ base: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: base * scale, weight: weight, design: design)
    }
}
