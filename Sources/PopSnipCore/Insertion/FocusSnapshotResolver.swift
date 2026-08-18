// MARK: - FocusSnapshotResolver.swift
// 前面アプリケーションのフォーカス中 UI 要素・選択テキストを解決する。
// timeSlice/Sources/timeSliceApp/AppStateSupport.swift の FrontmostSelectionTextResolver を
// 移植したもの。timeSlice 版は選択テキストの文字列のみを返すが、PopSnip では挿入エンジンが
// AXUIElement 自体を必要とするため、要素を保持したまま返す形に拡張している。

import AppKit
import ApplicationServices

/// 選択テキスト取得が失敗した場合のリカバリ（`AXManualAccessibility` 有効化 + 再試行）に
/// かけてよい待機量。Electron/Chromium 系アプリ（VS Code 等）はスクリーンリーダー等の
/// 支援技術から要求されない限りアクセシビリティツリーを構築しないため、
/// `kAXSelectedTextAttribute` が常に空になる。`AXManualAccessibility` 属性を明示的に
/// true 設定することでツリー構築を要求できるが、構築は対象アプリ側で非同期に進むため
/// 呼び出し経路のブロッキング許容量に応じて待機方針を変える。
public enum SelectionRecoveryBudget {
    /// リカバリしない（挿入直前の再解決など、選択テキストを使わない経路向け）。
    case none
    /// 有効化のうえ即時 1 回だけ再試行する。パネル表示直前など長時間ブロッキングできない経路向け。
    /// 一度有効化すればアプリ終了まで有効なため、初回は失敗しても次回以降は即時取得できる。
    case immediate
    /// 有効化後、ツリー構築の完了を短くポーリング待機する。クイック登録など
    /// ユーザーの明示操作でありある程度のブロッキングが許容できる経路向け。
    case brief(maxWaitMs: Int = 200)
}

/// パネル表示直前に「挿入先スナップショット」を作成するユーティリティ。
@MainActor
public enum FocusSnapshotResolver {
    /// `AXManualAccessibility` を有効化済みの pid。`.brief` のポーリング待機は
    /// pid ごと初回のみに限定し、2 回目以降（ツリー構築済み）で無駄な待機を避けるために使う。
    private static var manualAccessibilityEnabledPIDs: Set<pid_t> = []

    /// 現在の前面アプリケーションから `InsertionTarget` を解決する。
    /// Accessibility 権限が無い場合、または前面アプリが取得できない場合は nil を返す。
    public static func resolveCurrentTarget(
        recovery: SelectionRecoveryBudget = .none
    ) -> InsertionTarget? {
        guard AccessibilityPermission.isGranted() else {
            return nil
        }
        guard let runningApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return resolveTarget(for: runningApplication, recovery: recovery)
    }

    /// 指定アプリケーションから `InsertionTarget` を解決する。
    public static func resolveTarget(
        for runningApplication: NSRunningApplication,
        recovery: SelectionRecoveryBudget = .none
    ) -> InsertionTarget {
        let applicationElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        var focusedElement = resolveFocusedElement(from: applicationElement)
        var selectedText = focusedElement.map(resolveSelectedText) ?? ""

        let isRecoveryRequested: Bool
        if case .none = recovery {
            isRecoveryRequested = false
        } else {
            isRecoveryRequested = true
        }
        if isRecoveryRequested,
           shouldAttemptRecovery(hasFocusedElement: focusedElement != nil, selectedText: selectedText) {
            (focusedElement, selectedText) = attemptManualAccessibilityRecovery(
                applicationElement: applicationElement,
                pid: runningApplication.processIdentifier,
                recovery: recovery
            )
        }

        let security = resolveSecurity(of: focusedElement)
        return InsertionTarget(
            runningApplication: runningApplication,
            applicationElement: applicationElement,
            focusedElement: focusedElement,
            selectedText: selectedText,
            security: security
        )
    }

    /// リカバリ（`AXManualAccessibility` 有効化）を試みるべきかどうかの判定。
    /// AX 非依存の純粋関数として切り出し、単体テスト対象にする。
    static func shouldAttemptRecovery(hasFocusedElement: Bool, selectedText: String) -> Bool {
        hasFocusedElement == false || selectedText.isEmpty
    }

    /// `AXManualAccessibility` を有効化し、フォーカス要素・選択テキストを再取得する。
    private static func attemptManualAccessibilityRecovery(
        applicationElement: AXUIElement,
        pid: pid_t,
        recovery: SelectionRecoveryBudget
    ) -> (focusedElement: AXUIElement?, selectedText: String) {
        // 非対応アプリ（Electron/Chromium 以外）に設定しても AXError が返るだけで無害。
        // 対応アプリへの再設定も冪等なため、失敗検出時は毎回試みてよい。
        let setStatus = AXUIElementSetAttributeValue(
            applicationElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )

        func reresolve() -> (AXUIElement?, String) {
            let focusedElement = resolveFocusedElement(from: applicationElement)
            let selectedText = focusedElement.map(resolveSelectedText) ?? ""
            return (focusedElement, selectedText)
        }

        var (focusedElement, selectedText) = reresolve()

        guard
            setStatus == .success,
            case .brief(let maxWaitMs) = recovery,
            manualAccessibilityEnabledPIDs.insert(pid).inserted
        else {
            return (focusedElement, selectedText)
        }

        // ツリー構築は対象アプリ側のプロセスで進むため、こちらの main thread を
        // 短くポーリングしても対象アプリの構築を阻害しない
        // （ClipboardInserter.waitForPasteToSettle と同じ作法）。
        let pollIntervalMs = 50
        var elapsedMs = 0
        while shouldAttemptRecovery(hasFocusedElement: focusedElement != nil, selectedText: selectedText),
              elapsedMs < maxWaitMs {
            Thread.sleep(forTimeInterval: TimeInterval(pollIntervalMs) / 1000)
            elapsedMs += pollIntervalMs
            (focusedElement, selectedText) = reresolve()
        }
        return (focusedElement, selectedText)
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
        return unsafeDowncast(focusedElementValue, to: AXUIElement.self)
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
