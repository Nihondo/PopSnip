// MARK: - AccessibilityInserter.swift
// Accessibility API を使った直接挿入（挿入方式 A）。
// kAXSelectedTextAttribute へ書き込むことで、カーソル位置 / 選択範囲へテキストを挿入する。

import ApplicationServices
import Foundation

/// Accessibility API を使った直接挿入を担当する。
/// `FocusSnapshotResolver` の読み取りヘルパーを利用するため、同じく MainActor に固定する
/// （呼び出し元の `SnippetInsertionService` も MainActor）。
@MainActor
public enum AccessibilityInserter {
    private static let verificationPollIntervalMs = 8
    private static let verificationMaxWaitMs = 48

    /// `focusedElement` の選択範囲へ `text` を書き込む。
    ///
    /// 実機検証（docs/insertion_matrix.md）で判明した通り、Chrome の contenteditable /
    /// VS Code の Monaco Editor / Terminal のような一部アプリは `AXUIElementSetAttributeValue`
    /// が `.success` を返しつつ実際には何も書き込まない「見せかけの Accessibility 対応」である。
    /// この戻り値だけを信じると `SnippetInsertionService` が誤って成功と判断し、
    /// クリップボードフォールバックへ進まないまま何も挿入されない不具合になる。
    /// そのため書き込み後に `kAXValueAttribute` を読み戻し、実際に値が変化したかを確認してから
    /// 成否を返す。
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

        let valueBeforeInsertion = readValue(of: focusedElement)

        let setStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setStatus == .success else {
            return false
        }

        return verifyInsertionTookEffect(text, valueBeforeInsertion: valueBeforeInsertion, element: focusedElement)
    }

    /// 書き込み後に値を読み戻し、実際に反映されたかを確認する。
    /// アプリによっては AX ツリーの更新が非同期で数十ミリ秒遅れることがあるため、
    /// 短時間ポーリングする（ClipboardInserter の待機と同じ方式）。
    /// `kAXValueAttribute` 自体を公開していない要素（読み取り不可）の場合は検証手段が無いため、
    /// `setStatus` の成功をそのまま信じる。
    private static func verifyInsertionTookEffect(
        _ text: String,
        valueBeforeInsertion: String?,
        element: AXUIElement
    ) -> Bool {
        var elapsedMs = 0
        while true {
            let currentValue = readValue(of: element)
            if let currentValue {
                if currentValue.contains(text) || currentValue != valueBeforeInsertion {
                    return true
                }
            } else if valueBeforeInsertion == nil {
                return true
            }

            guard elapsedMs < verificationMaxWaitMs else {
                return false
            }
            Thread.sleep(forTimeInterval: TimeInterval(verificationPollIntervalMs) / 1000)
            elapsedMs += verificationPollIntervalMs
        }
    }

    private static func readValue(of element: AXUIElement) -> String? {
        guard
            let value = FocusSnapshotResolver.copyAttributeValue(of: element, attribute: kAXValueAttribute as CFString)
        else {
            return nil
        }
        return FocusSnapshotResolver.normalizeTextValue(value)
    }
}
