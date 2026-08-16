// MARK: - FocusSnapshotResolver.swift
// 前面アプリケーションのフォーカス中 UI 要素・選択テキストを解決する。
// timeSlice/Sources/timeSliceApp/AppStateSupport.swift の FrontmostSelectionTextResolver を
// 移植したもの。timeSlice 版は選択テキストの文字列のみを返すが、PopSnip では挿入エンジンが
// AXUIElement 自体を必要とするため、要素を保持したまま返す形に拡張している。

import AppKit
import ApplicationServices

/// パネル表示直前に「挿入先スナップショット」を作成するユーティリティ。
@MainActor
public enum FocusSnapshotResolver {
    /// 現在の前面アプリケーションから `InsertionTarget` を解決する。
    /// Accessibility 権限が無い場合、または前面アプリが取得できない場合は nil を返す。
    public static func resolveCurrentTarget() -> InsertionTarget? {
        guard AccessibilityPermission.isGranted() else {
            return nil
        }
        guard let runningApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return resolveTarget(for: runningApplication)
    }

    /// 指定アプリケーションから `InsertionTarget` を解決する。
    public static func resolveTarget(for runningApplication: NSRunningApplication) -> InsertionTarget {
        let applicationElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        let focusedElement = resolveFocusedElement(from: applicationElement)
        let selectedText = focusedElement.map(resolveSelectedText) ?? ""
        let security = resolveSecurity(of: focusedElement)
        return InsertionTarget(
            runningApplication: runningApplication,
            applicationElement: applicationElement,
            focusedElement: focusedElement,
            selectedText: selectedText,
            security: security
        )
    }

    // MARK: - フォーカス要素解決

    private static func resolveFocusedElement(from applicationElement: AXUIElement) -> AXUIElement? {
        guard
            let focusedElementValue = copyAttributeValue(
                of: applicationElement,
                attribute: kAXFocusedUIElementAttribute as CFString
            ),
            CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(focusedElementValue, to: AXUIElement.self)
    }

    // MARK: - 選択テキスト

    /// フォーカス中要素の選択テキストを取得する。
    /// timeSlice 版と異なり、複数行のスニペット本文として使うため改行・空白を正規化しない
    /// （前後の空白のみトリムする）。
    private static func resolveSelectedText(from focusedElement: AXUIElement) -> String {
        guard
            let selectedTextValue = copyAttributeValue(
                of: focusedElement,
                attribute: kAXSelectedTextAttribute as CFString
            ),
            let normalizedSelectedText = normalizeTextValue(selectedTextValue)
        else {
            return ""
        }
        return normalizedSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - セキュリティ分類

    /// secure text field（パスワード欄）かどうかを role / subrole から判定する。
    /// パスワード欄は role="AXTextField" + subrole="AXSecureTextField" として報告されるのが標準だが、
    /// アプリによっては role 自体が "AXSecureTextField" になる場合もあるため両方を見る。
    private static func resolveSecurity(of focusedElement: AXUIElement?) -> InsertionTargetSecurity {
        guard let focusedElement else {
            return .standard
        }
        let role = (copyAttributeValue(of: focusedElement, attribute: kAXRoleAttribute as CFString)) as? String
        let subrole = (copyAttributeValue(of: focusedElement, attribute: kAXSubroleAttribute as CFString)) as? String
        let secureIdentifier = kAXSecureTextFieldSubrole as String
        if role == secureIdentifier || subrole == secureIdentifier {
            return .secureTextField
        }
        return .standard
    }

    // MARK: - 共通ヘルパー

    static func copyAttributeValue(of element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var attributeValue: CFTypeRef?
        let copyStatus = AXUIElementCopyAttributeValue(element, attribute, &attributeValue)
        guard copyStatus == .success else {
            return nil
        }
        return attributeValue
    }

    static func normalizeTextValue(_ value: CFTypeRef) -> String? {
        if let plainText = value as? String {
            return plainText
        }
        if let attributedText = value as? NSAttributedString {
            return attributedText.string
        }
        return nil
    }
}
