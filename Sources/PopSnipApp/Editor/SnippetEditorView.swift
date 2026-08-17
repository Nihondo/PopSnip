// MARK: - SnippetEditorView.swift
// スニペットの登録・編集画面。タイトル（省略可）・本文（複数行）・タグを編集する。
// パネル起動時に前面アプリで選択されていたテキストがあれば、本文へ自動投入する
// （PopSnip_UI_plan.md「テキスト選択範囲がある状態で、スニペット登録を行うと、
// 選択範囲のテキストが本文に自動で入力される」）。

import AppKit
import SwiftUI

/// `SnippetEditorWindowController` はウインドウを使い回し `rootView` を差し替えるだけなので、
/// 同一ビュー identity のままだと `.onAppear` が再発火せず、2回目以降のクイック登録で
/// 選択範囲（`initialBody`）が本文へ反映されない不具合があった。
/// 呼び出しごとに一意な `sessionID` を発行し `.id(sessionID)` を与えることで、
/// rootView 差し替えのたびに `SnippetEditorContentView` を新規 identity として扱わせ、
/// `.onAppear` を確実に再発火させる（timeSlice の ManualCaptureCommentPanel は毎回ビューを
/// 新規生成することで同じ問題を回避している。ここではウインドウ使い回しの設計を保ったまま
/// 同等の効果を得る）。
struct SnippetEditorView: View {
    let store: SnippetStore
    let editingSnippetID: UUID?
    let initialBody: String
    let onFinish: () -> Void
    private let sessionID = UUID()

    var body: some View {
        SnippetEditorContentView(
            store: store,
            editingSnippetID: editingSnippetID,
            initialBody: initialBody,
            onFinish: onFinish
        )
        .id(sessionID)
    }
}

private struct SnippetEditorContentView: View {
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
    @State private var isFavorite = false
    @State private var isShowingDeleteConfirmation = false
    /// パレットからのクリック挿入でカーソル位置へ差し込むために保持する。
    @State private var bodyTextView: NSTextView?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            HStack {
                Text(editingSnippetID == nil ? L10n.string("editor.title.new") : L10n.string("editor.title.edit"))
                    .font(.title3.bold())
                Spacer()
                Toggle(isOn: $isFavorite) {
                    Label(L10n.string("editor.field.favorite"), systemImage: isFavorite ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help(L10n.string("editor.field.favorite"))
            }

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
                SnippetBodyTextView(text: $bodyDraft, onTextViewCreated: { bodyTextView = $0 })
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                PlaceholderPaletteView(onInsert: insertPlaceholder)
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
        .frame(minWidth: 480, minHeight: 500)
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

    /// タグ一覧の間隔を詰めるため、固定幅グリッドではなく実際の文字幅で折り返す
    /// TagFlowLayout を使う（UI_fix.md「スニペットの編集画面で、タグ一覧の間隔を詰める」）。
    private var tagPicker: some View {
        TagFlowLayout(spacing: 4, lineSpacing: 4) {
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

    /// パレットのチップがクリックされたときに、本文のカーソル位置へトークンを挿入する。
    /// `bodyTextView` 未生成（描画前）の場合は本文末尾への追記でフォールバックする。
    private func insertPlaceholder(_ token: String) {
        guard let bodyTextView else {
            bodyDraft += token
            return
        }
        let selectedRange = bodyTextView.selectedRange()
        guard bodyTextView.shouldChangeText(in: selectedRange, replacementString: token) else {
            return
        }
        bodyTextView.insertText(token, replacementRange: selectedRange)
        bodyTextView.didChangeText()
        bodyTextView.window?.makeFirstResponder(bodyTextView)
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
        isFavorite = existingSnippet.isFavorite
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
            tagIDs: Array(selectedTagIDs),
            isFavorite: isFavorite
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
