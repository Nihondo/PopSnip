// MARK: - SnippetInsertionService.swift
// 挿入方式 A（Accessibility API）→ B（Clipboard + Cmd+V）のフォールバックを統括する。
// secure text field（パスワード欄）への挿入は常に拒否する。

import AppKit
import ApplicationServices

/// 挿入方式の選択。設定画面（Phase 6）から変更可能にする前提のため、既定は `.automatic`。
public enum InsertionStrategy: String, Codable, Sendable {
    /// A → B の自動フォールバック（既定）。
    case automatic
    /// Accessibility API のみ（失敗しても Clipboard へフォールバックしない）。
    case accessibilityOnly
    /// 常に Clipboard + Cmd+V を使う。
    case clipboardOnly
}

/// 挿入結果。呼び出し側（パネル UI）が成否を表示に反映できるよう区別しておく。
public enum InsertionResult: Sendable {
    case insertedViaAccessibility
    case insertedViaClipboard
    case blockedBySecurity
    case noFocusedTarget
}

/// スニペット挿入のエントリポイント。
@MainActor
public enum SnippetInsertionService {
    /// `text` を `target` へ挿入する。
    /// - Parameters:
    ///   - target: パネル表示直前に取得したスナップショット。
    ///   - strategy: 挿入方式。既定は自動フォールバック。
    ///   - clipboardRestoreDelayMs: Clipboard 経由時の貼り付け待機時間（設定で調整可能にする前提）。
    ///   - caretUTF16Offset: `{{cursor}}` が指定していたキャレット位置（挿入テキスト先頭からの
    ///     UTF-16 オフセット）。Accessibility 経路で使う。プレースホルダを含まない呼び出しでは nil。
    ///   - caretCharacterOffsetFromEnd: 同じ位置を「挿入テキスト末尾から何文字戻るか」で表したもの。
    ///     Clipboard 経路（左矢印キー送出）で使う。
    @discardableResult
    public static func insert(
        _ text: String,
        into target: InsertionTarget,
        strategy: InsertionStrategy = .automatic,
        clipboardRestoreDelayMs: Int = ClipboardInserter.defaultRestoreDelayMs,
        caretUTF16Offset: Int? = nil,
        caretCharacterOffsetFromEnd: Int? = nil
    ) -> InsertionResult {
        guard target.isInsertionForbidden == false else {
            return .blockedBySecurity
        }

        // 元アプリへ復帰してから挿入する（パネルがフォーカスを奪っていた場合の保険）。
        target.runningApplication.activate()

        // フォーカスが変化している可能性があるため、挿入直前に再解決する。
        let freshTarget = FocusSnapshotResolver.resolveTarget(for: target.runningApplication)
        guard freshTarget.isInsertionForbidden == false else {
            return .blockedBySecurity
        }

        switch strategy {
        case .accessibilityOnly:
            guard let focusedElement = freshTarget.focusedElement else {
                return .noFocusedTarget
            }
            let didInsert = AccessibilityInserter.insert(text, into: focusedElement, caretUTF16Offset: caretUTF16Offset)
            return didInsert ? .insertedViaAccessibility : .noFocusedTarget

        case .clipboardOnly:
            ClipboardInserter.insert(
                text,
                restoreDelayMs: clipboardRestoreDelayMs,
                caretCharacterOffsetFromEnd: caretCharacterOffsetFromEnd
            )
            return .insertedViaClipboard

        case .automatic:
            if let focusedElement = freshTarget.focusedElement,
               AccessibilityInserter.insert(text, into: focusedElement, caretUTF16Offset: caretUTF16Offset) {
                return .insertedViaAccessibility
            }
            ClipboardInserter.insert(
                text,
                restoreDelayMs: clipboardRestoreDelayMs,
                caretCharacterOffsetFromEnd: caretCharacterOffsetFromEnd
            )
            return .insertedViaClipboard
        }
    }
}
