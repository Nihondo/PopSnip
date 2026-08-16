// MARK: - TagColorAssigner.swift
// タグ登録時の自動色割り当て。nihondo デザインパレットから未使用色を巡回割り当てする。
// 参照: ~/.claude/skills/nihondo-design/colors_and_type.css

import Foundation

/// タグの自動色割り当てを担当する。
public enum TagColorAssigner {
    /// nihondo デザインパレットから抜粋した、タグ用のカラーサイクル（#RRGGBB）。
    public static let palette: [String] = [
        "#7799DD", // brand
        "#16A34A", // success / timeslice green
        "#F59E0B", // warning amber
        "#E53935", // danger red
        "#8B5CF6", // coverzip purple
        "#0EA5E9", // info / leafmarq blue
        "#E040A0", // agentbooth pink
        "#6366F1", // comicapture indigo
        "#F97316", // apricot orange
        "#65A30D", // xojo-syntax olive
    ]

    /// 既存タグが使用している色を避けつつ、パレットを巡回して次の色を割り当てる。
    /// パレットを一巡して未使用色が無い場合は、使用回数が最も少ない色を返す。
    public static func nextColor(existingTags: [SnippetTag]) -> String {
        let usedColorCounts = existingTags.reduce(into: [String: Int]()) { counts, tag in
            counts[tag.colorHex, default: 0] += 1
        }

        if let unusedColor = palette.first(where: { usedColorCounts[$0] == nil }) {
            return unusedColor
        }

        let leastUsedColor = palette.min { lhs, rhs in
            (usedColorCounts[lhs] ?? 0) < (usedColorCounts[rhs] ?? 0)
        }
        return leastUsedColor ?? palette[0]
    }
}
