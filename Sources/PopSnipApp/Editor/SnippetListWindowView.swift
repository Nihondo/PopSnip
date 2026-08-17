// MARK: - SnippetListWindowView.swift
// スニペット一覧編集画面。複数選択でのタグ一括付与・削除、タグ管理を1画面にまとめる
// （PopSnip_UI_plan.md「一覧編集」）。

import SwiftUI

struct SnippetListWindowView: View {
    @ObservedObject var store: SnippetStore

    @State private var filterText = ""
    @State private var selection: Set<UUID> = []
    @State private var editingSnippetID: UUID?
    @State private var isShowingEditor = false
    @State private var isShowingBulkDeleteConfirmation = false
    @State private var isShowingBulkTagPopover = false
    @AppStorage(UserDefaultsKeys.panelFontSize) private var fontSize: AppFontSize = .medium

    var body: some View {
        NavigationSplitView {
            ScrollView {
                TagManagerView(store: store)
                    .padding(DesignTokens.Spacing.medium)
            }
            .frame(minWidth: 240)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                snippetTable
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .environment(\.appFontSize, fontSize)
        .sheet(isPresented: $isShowingEditor) {
            SnippetEditorView(
                store: store,
                editingSnippetID: editingSnippetID,
                initialBody: "",
                onFinish: { isShowingEditor = false }
            )
        }
        .alert(
            L10n.string("list.bulkDeleteConfirm.title"),
            isPresented: $isShowingBulkDeleteConfirmation
        ) {
            Button(L10n.string("editor.button.delete"), role: .destructive, action: deleteSelectedSnippets)
            Button(L10n.string("editor.button.cancel"), role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField(L10n.string("list.filter.placeholder"), text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Button {
                editingSnippetID = nil
                isShowingEditor = true
            } label: {
                Label(L10n.string("panel.footer.register"), systemImage: "plus")
            }

            if selection.isEmpty == false {
                bulkTagButton
                Button(role: .destructive) {
                    isShowingBulkDeleteConfirmation = true
                } label: {
                    Label(L10n.string("editor.button.delete"), systemImage: "trash")
                }
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.medium)
    }

    private var bulkTagButton: some View {
        Button {
            isShowingBulkTagPopover = true
        } label: {
            Label(L10n.string("list.bulkTag.menu"), systemImage: "tag")
        }
        .popover(isPresented: $isShowingBulkTagPopover) {
            BulkTagPopoverView(
                store: store,
                selectedSnippetIDs: selection,
                onApplyTag: applyTag(_:add:)
            )
        }
    }

    private var snippetTable: some View {
        List(selection: $selection) {
            ForEach(filteredSnippets) { snippet in
                snippetRow(snippet)
                    .tag(snippet.id)
                    .contextMenu {
                        Button(L10n.string("list.row.edit")) {
                            editingSnippetID = snippet.id
                            isShowingEditor = true
                        }
                        Button(L10n.string("editor.button.delete"), role: .destructive) {
                            store.deleteSnippet(id: snippet.id)
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.displayTitle)
                    .scaledFont(DesignTokens.Typography.rowTitle, weight: .medium)
                Text(snippet.body)
                    .scaledFont(DesignTokens.Typography.rowBody)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(tags(for: snippet)) { tag in
                        TagChipView(tag: tag)
                    }
                }
            }
            Spacer()
            Text("×\(snippet.usageCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                store.toggleFavorite(id: snippet.id)
            } label: {
                Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(snippet.isFavorite ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
        }
        // 行内の Text / TagChipView がヒットテストを吸ってしまい、空白部分のクリックで
        // 選択できない不具合があった（UI_fix.md「空白をクリック選択しないとセル選択にならない」）。
        // 行全体を単一のヒット領域にし、左右の余白も広げる。
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // ダブルクリックでの編集起動は List(selection:) のネイティブなクリック選択・矢印キー
        // ナビゲーションと競合し、選択不能/反応遅延の原因になっていた（timeSlice の
        // CaptureViewerView も同じ理由でリスト行にダブルクリック検出を持たない設計）。
        // 編集は右クリックのコンテキストメニューで行う。
    }

    private var filteredSnippets: [Snippet] {
        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFilter.isEmpty == false else {
            return store.library.snippets.sorted { $0.updatedAt > $1.updatedAt }
        }
        return SnippetSearchEngine.search(
            query: trimmedFilter,
            in: store.library.snippets,
            tags: store.library.tags,
            sortOrder: .relevance,
            limit: store.library.snippets.count
        ).map(\.snippet)
    }

    private func tags(for snippet: Snippet) -> [SnippetTag] {
        store.library.tags.filter { snippet.tagIDs.contains($0.id) }
    }

    private func applyTag(_ tagID: UUID, add: Bool) {
        for snippetID in selection {
            guard var snippet = store.library.snippets.first(where: { $0.id == snippetID }) else {
                continue
            }
            if add {
                if snippet.tagIDs.contains(tagID) == false {
                    snippet.tagIDs.append(tagID)
                }
            } else {
                snippet.tagIDs.removeAll { $0 == tagID }
            }
            store.upsertSnippet(snippet)
        }
    }

    private func deleteSelectedSnippets() {
        for snippetID in selection {
            store.deleteSnippet(id: snippetID)
        }
        selection.removeAll()
    }
}
