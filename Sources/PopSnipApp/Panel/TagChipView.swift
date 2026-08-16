// MARK: - TagChipView.swift
// タグを角丸矩形で表示するチップ。タグごとに色が変わる（PopSnip_UI_plan.md の要件）。

import SwiftUI

struct TagChipView: View {
    let tag: SnippetTag

    var body: some View {
        Text(tag.name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tagColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tagColor.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tagColor.opacity(0.35), lineWidth: 1)
            )
    }

    private var tagColor: Color {
        Color(hex: tag.colorHex) ?? .accentColor
    }
}

extension Color {
    /// "#RRGGBB" 形式の16進数文字列から Color を生成する。
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        guard hexString.count == 6, let hexValue = UInt64(hexString, radix: 16) else {
            return nil
        }
        let red = Double((hexValue & 0xFF0000) >> 16) / 255
        let green = Double((hexValue & 0x00FF00) >> 8) / 255
        let blue = Double(hexValue & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
