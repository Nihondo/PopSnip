// MARK: - PasteboardSnapshotTests.swift
// PasteboardSnapshot の退避・復元往復と、changeCount 不変時の no-op 動作を検証する。
// AppKit の実クリップボードに影響しないよう、専用の NSPasteboard を都度生成して使う。

import AppKit
import Testing
@testable import PopSnip

@Suite("PasteboardSnapshot")
@MainActor
struct PasteboardSnapshotTests {
    private func makeTemporaryPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("popsnip-test-\(UUID().uuidString)"))
    }

    @Test("退避後に書き換えても、復元で元の文字列に戻る")
    func restoreRestoresOriginalString() {
        let pasteboard = makeTemporaryPasteboard()
        pasteboard.clearContents()
        pasteboard.setString("元の内容", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("書き換え後", forType: .string)

        snapshot.restore(to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "元の内容")
    }

    @Test("退避後に何も書き込まれなければ、復元は何もしない（changeCount 不変）")
    func restoreIsNoOpWhenChangeCountUnchanged() {
        let pasteboard = makeTemporaryPasteboard()
        pasteboard.clearContents()
        pasteboard.setString("そのまま", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let changeCountBeforeRestore = pasteboard.changeCount

        snapshot.restore(to: pasteboard)

        #expect(pasteboard.changeCount == changeCountBeforeRestore)
        #expect(pasteboard.string(forType: .string) == "そのまま")
    }

    @Test("退避時点でクリップボードが空だった場合、復元後も空のまま維持される")
    func restoreKeepsEmptyWhenCapturedEmpty() {
        let pasteboard = makeTemporaryPasteboard()
        pasteboard.clearContents()

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("一時的な内容", forType: .string)

        snapshot.restore(to: pasteboard)

        #expect(pasteboard.string(forType: .string) == nil)
    }
}
