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
    @State private var isAddingTag = false
    @State private var newTagName = ""
    @FocusState private var isNewTagFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.string("tagManager.title"))
                    .font(.headline)
                Spacer()
                Button {
                    isAddingTag = true
                    isNewTagFieldFocused = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help(L10n.string("tagManager.addTag"))
            }

            if isAddingTag {
                newTagField
            }

            if store.library.tags.isEmpty, isAddingTag == false {
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
            colorSwatchButton(for: tag)

            if renamingTagID == tag.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { commitRename(tag) }
                Button {
                    commitRename(tag)
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.plain)
                .help(L10n.string("editor.button.save"))
                Button {
                    renamingTagID = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help(L10n.string("editor.button.cancel"))
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

    /// タグ色の選択 UI。カラーコード文字列ではなく色の矩形を並べて選ばせる
    /// （UI_fix.md「タグの色を変える場合のUIはカラーコードではなく、色の矩形を表示する」）。
    private func colorSwatchButton(for tag: SnippetTag) -> some View {
        ColorSwatchPopoverButton(
            selectedColorHex: tag.colorHex,
            onSelectColor: { colorHex in
                var updatedTag = tag
                updatedTag.colorHex = colorHex
                store.upsertTag(updatedTag)
            }
        )
    }

    private var newTagField: some View {
        HStack(spacing: 6) {
            TextField(L10n.string("tagManager.newTag.placeholder"), text: $newTagName)
                .textFieldStyle(.roundedBorder)
                .focused($isNewTagFieldFocused)
                .onSubmit(commitNewTag)
            Button(L10n.string("editor.button.save"), action: commitNewTag)
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(L10n.string("editor.button.cancel")) {
                isAddingTag = false
                newTagName = ""
            }
        }
    }

    private func commitNewTag() {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return
        }
        _ = store.createTag(name: trimmedName)
        newTagName = ""
        isAddingTag = false
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

/// 現在の色を示す丸ボタン。押すと `TagColorAssigner.palette` を色矩形で並べた popover を開く。
private struct ColorSwatchPopoverButton: View {
    let selectedColorHex: String
    let onSelectColor: (String) -> Void

    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover = true
        } label: {
            Circle()
                .fill(Color(hex: selectedColorHex) ?? .gray)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 5), spacing: 6) {
                ForEach(TagColorAssigner.palette, id: \.self) { colorHex in
                    Button {
                        onSelectColor(colorHex)
                        isShowingPopover = false
                    } label: {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(hex: colorHex) ?? .gray)
                            .frame(width: 36, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(
                                        Color.primary,
                                        lineWidth: colorHex == selectedColorHex ? 2 : 0
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.small)
        }
    }
}
