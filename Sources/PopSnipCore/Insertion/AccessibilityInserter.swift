// MARK: - AccessibilityInserter.swift
// Accessibility API を使った直接挿入（挿入方式 A）。
// kAXSelectedTextAttribute へ書き込むことで、カーソル位置 / 選択範囲へテキストを挿入する。

import ApplicationServices

/// Accessibility API を使った直接挿入を担当する。
public enum AccessibilityInserter {
    /// `focusedElement` の選択範囲へ `text` を書き込む。
    /// 成功可否は `AXUIElementSetAttributeValue` の戻り値で判定する
    /// （一部アプリは成功を返しつつ実際には反映しないため、最終的な成否は
    /// Phase 1 の手動検証マトリクスで確認する）。
    @discardableResult
    public static func insert(_ text: String, into focusedElement: AXUIElement) -> Bool {
        var isSettable: DarwinBoolean = false
        let settableStatus = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        guard settableStatus == .success, isSettable.boolValue else {
            return false
        }

        let setStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return setStatus == .success
    }
}
