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
                bulkTagMenu
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

    private var bulkTagMenu: some View {
        Menu {
            ForEach(store.library.tags) { tag in
                Button(L10n.format("list.bulkTag.add", tag.name)) {
                    applyTag(tag.id, add: true)
                }
                Button(L10n.format("list.bulkTag.remove", tag.name)) {
                    applyTag(tag.id, add: false)
                }
            }
        } label: {
            Label(L10n.string("list.bulkTag.menu"), systemImage: "tag")
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
                    .font(.system(size: 13, weight: .medium))
                Text(snippet.body)
                    .font(.system(size: 11))
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
        }
        .padding(.vertical, 2)
        .onTapGesture(count: 2) {
            editingSnippetID = snippet.id
            isShowingEditor = true
        }
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
