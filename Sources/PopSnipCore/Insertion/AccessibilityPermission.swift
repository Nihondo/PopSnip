// MARK: - AccessibilityPermission.swift
// Accessibility（アクセシビリティ）権限の確認・要求。
// timeSlice/Sources/timeSliceApp/AppStateSupport.swift の FrontmostSelectionTextResolver
// から権限まわりのロジックを移植したもの。

// ApplicationServices は Swift 6 の並行性チェックに対応した形で監査されていないフレームワークのため、
// `kAXTrustedCheckOptionPrompt`（Unmanaged<CFString>! のグローバル変数）を素直に import すると
// 「共有可変状態」として並行性エラーになる。`@preconcurrency` を付けて、この import から得られる
// シンボルを Swift 6 以前と同様に扱う。
@preconcurrency import ApplicationServices

/// アプリの Accessibility 権限状態を確認・要求するユーティリティ。
public enum AccessibilityPermission {
    /// 現在 Accessibility 権限が許可されているか（プロンプトは出さない）。
    public static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// システム設定への誘導プロンプトを表示しつつ権限状態を返す。
    /// 未許可の場合、システム設定「プライバシーとセキュリティ > アクセシビリティ」への案内が表示される。
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let promptOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(promptOptions)
    }
}
