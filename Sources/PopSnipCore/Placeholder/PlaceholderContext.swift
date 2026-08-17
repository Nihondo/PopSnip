// MARK: - PlaceholderContext.swift
// プレースホルダ展開に必要な「挿入時点の状態」を1つにまとめた値型。
// 値型にしてあるのは、テストから時刻・クリップボード内容などを固定値で注入できるようにするため
// （`PlaceholderExpander` 自体は Date() や NSPasteboard に直接触れない）。

import AppKit
import Foundation

/// プレースホルダ展開の材料となる文脈情報。
public struct PlaceholderContext: Sendable {
    public var now: Date
    public var clipboardText: String
    public var selectedText: String
    public var appName: String
    public var locale: Locale
    public var timeZone: TimeZone

    public init(
        now: Date = Date(),
        clipboardText: String = "",
        selectedText: String = "",
        appName: String = "",
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.now = now
        self.clipboardText = clipboardText
        self.selectedText = selectedText
        self.appName = appName
        self.locale = locale
        self.timeZone = timeZone
    }
}

@MainActor
public extension PlaceholderContext {
    /// 挿入直前に呼ぶ。`ClipboardInserter` がクリップボードの内容を書き換える前に読み取る
    /// 必要があるため（`{{clipboard}}` は挿入前のユーザーのクリップボードを指す）、
    /// `SnippetInsertionService.insert` を呼ぶ前にこの関数で文脈を確定させておくこと。
    static func capture(from target: InsertionTarget, now: Date = Date()) -> PlaceholderContext {
        PlaceholderContext(
            now: now,
            clipboardText: NSPasteboard.general.string(forType: .string) ?? "",
            selectedText: target.selectedText,
            appName: target.runningApplication.localizedName ?? "",
            locale: .current,
            timeZone: .current
        )
    }
}
