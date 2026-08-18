// MARK: - FocusSnapshotResolverTests.swift
// AXManualAccessibility リカバリの発火条件（shouldAttemptRecovery）を検証する。
// AX / CGEvent に依存する取得本体は自動テスト対象外（CLAUDE.md 記載どおり手動検証で担保する）。

import Testing
@testable import PopSnip

@Suite("FocusSnapshotResolver.shouldAttemptRecovery")
@MainActor
struct FocusSnapshotResolverTests {
    @Test("フォーカス要素があり選択テキストも非空なら、リカバリは不要")
    func noRecoveryWhenTextPresent() {
        #expect(FocusSnapshotResolver.shouldAttemptRecovery(hasFocusedElement: true, selectedText: "選択中の文字列") == false)
    }

    @Test("フォーカス要素が取得できなければ、リカバリが必要")
    func recoveryNeededWhenNoFocusedElement() {
        #expect(FocusSnapshotResolver.shouldAttemptRecovery(hasFocusedElement: false, selectedText: "") == true)
    }

    @Test("フォーカス要素はあるが選択テキストが空なら、リカバリが必要")
    func recoveryNeededWhenSelectedTextEmpty() {
        #expect(FocusSnapshotResolver.shouldAttemptRecovery(hasFocusedElement: true, selectedText: "") == true)
    }
}
