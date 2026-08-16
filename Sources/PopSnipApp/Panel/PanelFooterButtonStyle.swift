// MARK: - PanelFooterButtonStyle.swift
// パネルフッターの「登録」「一覧」「設定」ボタン用のスタイル。
// 角丸矩形で囲んでボタンだと認識しやすくし、パディング部分もクリックできるようにする
// （UI_fix.md「文字をクリックしないとボタンが押せない問題」への対応）。
// .buttonStyle(.plain) のままだと Label の描画領域しかヒットテスト対象にならないため、
// パディングを付けたあとに contentShape(Rectangle()) でヒット領域自体を広げる。

import SwiftUI

struct PanelFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}
