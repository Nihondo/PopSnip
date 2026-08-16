// MARK: - InsertionTarget.swift
// パネル表示直前に取得する「挿入先スナップショット」。
// パネルが前面アプリのフォーカスを奪わない設計だが、環境によっては奪われる場合の保険として、
// パネル表示直前の frontmost app / フォーカス中 UI 要素 / 選択テキストを保持しておく。

import AppKit
import ApplicationServices

/// 挿入先の入力欄が secure text field（パスワード欄等）かどうかを表す。
public enum InsertionTargetSecurity {
    case standard
    case secureTextField
}

/// パネル表示直前に確定させる挿入先の情報。
/// AXUIElement を保持するため MainActor 上でのみ生成・使用する。
@MainActor
public struct InsertionTarget {
    /// フォーカスを保持していた前面アプリケーション。
    public let runningApplication: NSRunningApplication
    /// `runningApplication` のプロセス ID から作成した AXUIElement（アプリケーション要素）。
    public let applicationElement: AXUIElement
    /// 取得できた場合の、フォーカス中 UI 要素。
    public let focusedElement: AXUIElement?
    /// フォーカス中 UI 要素で選択されていたテキスト（無ければ空文字）。
    public let selectedText: String
    /// フォーカス中 UI 要素のセキュリティ分類。secure text field なら挿入を必ず拒否する。
    public let security: InsertionTargetSecurity

    public init(
        runningApplication: NSRunningApplication,
        applicationElement: AXUIElement,
        focusedElement: AXUIElement?,
        selectedText: String,
        security: InsertionTargetSecurity
    ) {
        self.runningApplication = runningApplication
        self.applicationElement = applicationElement
        self.focusedElement = focusedElement
        self.selectedText = selectedText
        self.security = security
    }

    /// パスワード欄など、アプリとして挿入してはならない対象かどうか。
    public var isInsertionForbidden: Bool {
        security == .secureTextField
    }
}
