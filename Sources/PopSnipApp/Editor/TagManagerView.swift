// MARK: - TagManagerView.swift
// タグの一括編集: 名前変更（ID 参照のため全スニペットへ自動反映）、色変更、削除。
// PopSnip_UI_plan.md「タグ名の変更も可能で、変更後は全てのスニペットに反映される」
// 「タグの色も変更可能」に対応する。

import SwiftUI

struct TagManagerView: View {
    @ObservedObject var store: SnippetStore

    @State private var renamingTagID: UUID?
    @State private var renameText = ""
    @State private var tagPendingDeletion: SnippetTag?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("tagManager.title"))
                .font(.headline)

            if store.library.tags.isEmpty {
                Text(L10n.string("tagManager.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(store.library.tags) { tag in
                tagRow(tag)
            }
        }
        .alert(
            L10n.string("tagManager.deleteConfirm.title"),
            isPresented: $isShowingDeleteConfirmation,
            presenting: tagPendingDeletion
        ) { tag in
            Button(L10n.string("editor.button.delete"), role: .destructive) {
                store.deleteTag(id: tag.id)
            }
            Button(L10n.string("editor.button.cancel"), role: .cancel) {}
        } message: { tag in
            Text(L10n.format("tagManager.deleteConfirm.message", tag.name))
        }
    }

    private func tagRow(_ tag: SnippetTag) -> some View {
        HStack(spacing: 8) {
            colorSwatchMenu(for: tag)

            if renamingTagID == tag.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit { commitRename(tag) }
                Button(L10n.string("editor.button.save")) { commitRename(tag) }
                Button(L10n.string("editor.button.cancel")) { renamingTagID = nil }
            } else {
                TagChipView(tag: tag)
                    .onTapGesture { beginRename(tag) }
            }

            Text("\(snippetCount(for: tag.id))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                tagPendingDeletion = tag
                isShowingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private func colorSwatchMenu(for tag: SnippetTag) -> some View {
        Menu {
            ForEach(TagColorAssigner.palette, id: \.self) { colorHex in
                Button {
                    var updatedTag = tag
                    updatedTag.colorHex = colorHex
                    store.upsertTag(updatedTag)
                } label: {
                    Label {
                        Text(colorHex)
                    } icon: {
                        Circle().fill(Color(hex: colorHex) ?? .gray)
                    }
                }
            }
        } label: {
            Circle()
                .fill(Color(hex: tag.colorHex) ?? .gray)
                .frame(width: 14, height: 14)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
    }

    private func beginRename(_ tag: SnippetTag) {
        renamingTagID = tag.id
        renameText = tag.name
    }

    private func commitRename(_ tag: SnippetTag) {
        defer { renamingTagID = nil }
        let trimmedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false, trimmedName != tag.name else {
            return
        }
        var updatedTag = tag
        updatedTag.name = trimmedName
        store.upsertTag(updatedTag)
    }

    private func snippetCount(for tagID: UUID) -> Int {
        store.library.snippets.filter { $0.tagIDs.contains(tagID) }.count
    }
}
