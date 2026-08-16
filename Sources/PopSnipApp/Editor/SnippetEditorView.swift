// MARK: - SnippetEditorView.swift
// スニペットの登録・編集画面。タイトル（省略可）・本文（複数行）・タグを編集する。
// パネル起動時に前面アプリで選択されていたテキストがあれば、本文へ自動投入する
// （PopSnip_UI_plan.md「テキスト選択範囲がある状態で、スニペット登録を行うと、
// 選択範囲のテキストが本文に自動で入力される」）。

import SwiftUI

struct SnippetEditorView: View {
    @ObservedObject var store: SnippetStore
    /// 編集対象。nil の場合は新規登録。
    let editingSnippetID: UUID?
    let initialBody: String
    let onFinish: () -> Void

    @State private var title = ""
    // View プロトコルが要求する `body` と名前が衝突するため、本文は `bodyDraft` という名前にする。
    @State private var bodyDraft = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var newTagName = ""
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            Text(editingSnippetID == nil ? L10n.string("editor.title.new") : L10n.string("editor.title.edit"))
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("editor.field.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L10n.string("editor.field.title.placeholder"), text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("editor.field.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $bodyDraft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("editor.field.tags"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                tagPicker

                HStack {
                    TextField(L10n.string("editor.field.newTag.placeholder"), text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(createTagFromInput)
                    Button(L10n.string("editor.button.addTag"), action: createTagFromInput)
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Spacer(minLength: 0)

            HStack {
                if editingSnippetID != nil {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Text(L10n.string("editor.button.delete"))
                    }
                }
                Spacer()
                Button(L10n.string("editor.button.cancel")) {
                    onFinish()
                }
                Button(L10n.string("editor.button.save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.large)
        .frame(minWidth: 480, minHeight: 420)
        .onAppear(perform: loadInitialState)
        .alert(
            L10n.string("editor.deleteConfirm.title"),
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button(L10n.string("editor.button.delete"), role: .destructive, action: delete)
            Button(L10n.string("editor.button.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("editor.deleteConfirm.message"))
        }
    }

    private var tagPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(store.library.tags) { tag in
                Button {
                    toggleTag(tag.id)
                } label: {
                    TagChipView(tag: tag)
                        .opacity(selectedTagIDs.contains(tag.id) ? 1 : 0.35)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleTag(_ tagID: UUID) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
        } else {
            selectedTagIDs.insert(tagID)
        }
    }

    private func createTagFromInput() {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            return
        }
        if let existingTag = store.library.tags.first(where: { $0.name == trimmedName }) {
            selectedTagIDs.insert(existingTag.id)
        } else {
            let createdTag = store.createTag(name: trimmedName)
            selectedTagIDs.insert(createdTag.id)
        }
        newTagName = ""
    }

    private func loadInitialState() {
        guard
            let editingSnippetID,
            let existingSnippet = store.library.snippets.first(where: { $0.id == editingSnippetID })
        else {
            bodyDraft = initialBody
            return
        }
        title = existingSnippet.title ?? ""
        bodyDraft = existingSnippet.body
        selectedTagIDs = Set(existingSnippet.tagIDs)
    }

    private func save() {
        let trimmedBody = bodyDraft
        guard trimmedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = Snippet(
            id: editingSnippetID ?? UUID(),
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            body: trimmedBody,
            tagIDs: Array(selectedTagIDs)
        )
        store.upsertSnippet(snippet)
        onFinish()
    }

    private func delete() {
        guard let editingSnippetID else {
            return
        }
        store.deleteSnippet(id: editingSnippetID)
        onFinish()
    }
}
