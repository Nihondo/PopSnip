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
    ///
    /// - Parameter caretUTF16Offset: `{{cursor}}` プレースホルダが指定していたキャレット位置
    ///   （`text` 先頭からの UTF-16 オフセット）。挿入の検証に成功した後、ベストエフォートで
    ///   `kAXSelectedTextRangeAttribute` へ書き戻す。この属性を読み書きできない要素では
    ///   キャレット位置の指定だけを諦め、挿入自体の成否には影響させない。
    @discardableResult
    public static func insert(_ text: String, into focusedElement: AXUIElement, caretUTF16Offset: Int? = nil) -> Bool {
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
        // 挿入で置き換えられる選択範囲の開始位置。挿入後のキャレット位置はここからの相対オフセット。
        let selectionRangeBeforeInsertion = selectionRange(of: focusedElement)

        let setStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setStatus == .success else {
            return false
        }

        let didInsert = verifyInsertionTookEffect(text, valueBeforeInsertion: valueBeforeInsertion, element: focusedElement)
        guard didInsert else {
            return false
        }

        if let caretUTF16Offset {
            moveCaret(
                of: focusedElement,
                toOffset: caretUTF16Offset,
                relativeToLocation: selectionRangeBeforeInsertion?.location ?? 0
            )
        }
        return true
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

    // MARK: - キャレット位置

    /// `kAXSelectedTextRangeAttribute` を読み取り、選択範囲（無ければ挿入点）を返す。
    /// この属性を公開していない要素では nil。
    private static func selectionRange(of element: AXUIElement) -> CFRange? {
        guard
            let value = FocusSnapshotResolver.copyAttributeValue(
                of: element,
                attribute: kAXSelectedTextRangeAttribute as CFString
            ),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = value as! AXValue // swiftlint:disable:this force_cast
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    /// 挿入後、`kAXSelectedTextRangeAttribute` へキャレット位置を書き戻す（ベストエフォート）。
    /// 失敗しても挿入自体は既に完了しているため、呼び出し元には何も返さない。
    private static func moveCaret(of element: AXUIElement, toOffset offset: Int, relativeToLocation baseLocation: Int) {
        var newRange = CFRange(location: baseLocation + offset, length: 0)
        guard let newRangeValue = AXValueCreate(.cfRange, &newRange) else {
            return
        }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
    }
}
