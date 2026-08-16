// MARK: - AppLogger.swift
// アプリ全体で使う構造化ロガー。Console.app と連携する。
// AgentLimits/AgentLimits/App/AppLogger.swift と同じパターン。
//
// 使用例:
// ```swift
// Logger.storage.error("スニペットファイルの読み込みに失敗: \(error.localizedDescription)")
// ```
//
// ログ収集（サポート用）:
// ```bash
// log show --predicate 'subsystem == "com.dmng.popsnip"' --last 1h
// ```

import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.dmng.popsnip"

    /// アプリ全体: 起動・設定・ログイン項目
    static let app = Logger(subsystem: subsystem, category: "app")

    /// スニペット挿入: Accessibility API / Clipboard フォールバック
    static let insertion = Logger(subsystem: subsystem, category: "insertion")

    /// スニペットストレージ: JSON 読み書き・外部編集の検知
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// グローバルショートカット: ホットキー登録・配送
    static let shortcut = Logger(subsystem: subsystem, category: "shortcut")

    /// パネル UI: 表示・検索・キー操作
    static let panel = Logger(subsystem: subsystem, category: "panel")
}
