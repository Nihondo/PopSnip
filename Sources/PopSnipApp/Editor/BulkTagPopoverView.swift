// MARK: - BulkTagPopoverView.swift
// 一覧編集画面で選択中の複数スニペットへタグを一括付与/削除する popover。
// 「タグ」を付与／「タグ」を削除という2行メニューではなく、角丸表示のタグチップを
// クリックして ON/OFF を切り替える UI にする（UI_fix.md「タグ」プルダウンの改善）。
// タグごとの状態は選択中スニペット全体の付与状況から「全部/一部/なし」の3値で決まり、
// クリックのたびに「全部持たせる」か「全部から外す」かのどちらかへ倒す。

import SwiftUI

struct BulkTagPopoverView: View {
    @ObservedObject var store: SnippetStore
    let selectedSnippetIDs: Set<UUID>
    let onApplyTag: (_ tagID: UUID, _ shouldAdd: Bool) -> Void

    @State private var newTagName = ""

    private enum TagAssignmentState {
        case all
        case partial
        case none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("list.bulkTag.popover.title"))
                .font(.headline)

            if store.library.tags.isEmpty {
                Text(L10n.string("tagManager.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TagFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(store.library.tags) { tag in
                        tagToggleChip(tag)
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                TextField(L10n.string("list.bulkTag.newTag.placeholder"), text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createAndApplyTag)
                Button(action: createAndApplyTag) {
                    Image(systemName: "plus")
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(minWidth: 260, maxWidth: 320)
    }

    private func tagToggleChip(_ tag: SnippetTag) -> some View {
        let assignmentState = state(for: tag)
        return Button {
            toggleTag(tag)
        } label: {
            TagChipView(tag: tag)
                .opacity(assignmentState == .none ? 0.35 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 1.5, dash: assignmentState == .partial ? [3, 2] : [])
                        )
                        .opacity(assignmentState == .none ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func state(for tag: SnippetTag) -> TagAssignmentState {
        let selectedSnippets = store.library.snippets.filter { selectedSnippetIDs.contains($0.id) }
        guard selectedSnippets.isEmpty == false else {
            return .none
        }
        let taggedCount = selectedSnippets.filter { $0.tagIDs.contains(tag.id) }.count
        if taggedCount == 0 {
            return .none
        }
        if taggedCount == selectedSnippets.count {
            return .all
        }
        return .partial
    }

    private func toggleTag(_ tag: SnippetTag) {
        let shouldAdd = state(for: tag) != .all
        onApplyTag(tag.id, shouldAdd)
    }

    private func createAndApplyTag() {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return
        }
        let tagID: UUID
        if let existingTag = store.library.tags.first(where: { $0.name == trimmedName }) {
            tagID = existingTag.id
        } else {
            tagID = store.createTag(name: trimmedName).id
        }
        onApplyTag(tagID, true)
        newTagName = ""
    }
}
