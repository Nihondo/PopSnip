// MARK: - SnippetPanelView.swift
// 検索ボックス → タグ候補 / スニペット結果 → フッターで構成する。
// キー入力は SnippetPanelPresenter の NSEvent モニタで一元化し、
// IME 変換中はパネル側のナビゲーションより入力システムを優先する。

import AppKit
import SwiftUI

private let panelCornerRadius: CGFloat = 16

struct SnippetPanelView: View {
    @ObservedObject var store: SnippetStore
    @ObservedObject var viewModel: SnippetPanelViewModel
    let onOpenEditor: (_ editingSnippetID: UUID?) -> Void
    let onOpenList: () -> Void
    let onOpenSettings: () -> Void
    let onDeleteSnippet: (Snippet) -> Void
    let onSearchFieldCreated: (NSTextField) -> Void

    @Environment(\.appFontSize) private var appFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider().opacity(0.5)
            resultsList
            Divider().opacity(0.5)
            footer
        }
        .frame(minWidth: DesignTokens.WindowSize.panelMinWidth, minHeight: DesignTokens.WindowSize.panelMinHeight)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 10)
        .onAppear {
            store.reloadIfNeeded()
            viewModel.resetSelectionForContentChange()
        }
        .onChange(of: viewModel.queryText) { _, _ in
            viewModel.resetSelectionForContentChange()
        }
        .onChange(of: viewModel.selectedTagIDs) { _, _ in
            viewModel.resetSelectionForContentChange()
        }
    }

    // MARK: - 検索ボックス

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            IMESafeSearchField(
                text: $viewModel.queryText,
                placeholder: L10n.string("panel.search.placeholder"),
                fontSize: DesignTokens.Typography.searchField * appFontSize.scale,
                onFieldCreated: onSearchFieldCreated
            )
            .frame(height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 結果表示

    private var resultsList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if viewModel.isSearching || viewModel.isDrilledDown {
                        scopedContent
                    } else {
                        browsingContent
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: viewModel.highlightedItemID) { _, highlightedItemID in
                guard let highlightedItemID else {
                    return
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    scrollProxy.scrollTo(highlightedItemID, anchor: .center)
                }
            }
        }
    }

    /// 検索中またはタグドリルダウン中の共通表示。
    @ViewBuilder
    private var scopedContent: some View {
        if viewModel.isDrilledDown {
            BackRowView(tags: viewModel.selectedTags, isSelected: viewModel.isBackSelected())
                .onTapGesture { viewModel.goBackOneLevel() }
                .id(PanelListItem.backItemID)
        }

        if viewModel.visibleTagCandidates.isEmpty == false {
            if viewModel.isSearching {
                sectionHeader(L10n.string("panel.section.tags"))
            }
            tagCandidateContent(viewModel.visibleTagCandidates)
        }

        ForEach(Array(viewModel.scopedSnippetItems.enumerated()), id: \.element.id) { ordinal, item in
            snippetRow(for: item, searchOrdinal: viewModel.isSearching ? ordinal + 1 : nil)
                .id(item.id)
        }
    }

    /// 検索語もタグ絞り込みもない場合は、設定されたセクション順を保つ。
    private var browsingContent: some View {
        ForEach(viewModel.preferences.orderedEnabledSections) { section in
            sectionView(for: section)
        }
    }

    @ViewBuilder
    private func sectionView(for section: PanelSection) -> some View {
        switch section {
        case .tags:
            if viewModel.visibleTagCandidates.isEmpty == false {
                sectionHeader(L10n.string("panel.section.tags"))
                tagCandidateContent(viewModel.visibleTagCandidates)
            }
        case .recents:
            snippetSection(
                titleKey: "panel.section.recents",
                snippets: viewModel.recentSnippets(),
                context: section.rawValue
            )
        case .allSnippets:
            snippetSection(
                titleKey: "panel.section.allSnippets",
                snippets: viewModel.allSnippets(),
                context: section.rawValue
            )
        case .favorites:
            snippetSection(
                titleKey: "panel.section.favorites",
                snippets: viewModel.favoriteSnippets(),
                context: section.rawValue
            )
        }
    }

    @ViewBuilder
    private func tagCandidateContent(_ candidates: [PanelTagCandidate]) -> some View {
        switch viewModel.preferences.tagLayoutStyle {
        case .horizontalStrip:
            TagStripView(
                candidates: candidates,
                selectedTagID: viewModel.highlightedTagID,
                onSelect: viewModel.drillIntoTag
            )
            .id(PanelListItem.tagStripItemID)
        case .verticalList:
            ForEach(candidates) { candidate in
                TagRowView(
                    tag: candidate.tag,
                    snippetCount: candidate.snippetCount,
                    isSelected: viewModel.isTagSelected(candidate.id)
                )
                .onTapGesture { viewModel.drillIntoTag(candidate.id) }
                .id(PanelListItem.tagItemID(candidate.id))
            }
        }
    }

    @ViewBuilder
    private func snippetSection(titleKey: String, snippets: [Snippet], context: String) -> some View {
        if snippets.isEmpty == false {
            sectionHeader(L10n.string(titleKey))
            ForEach(snippets) { snippet in
                snippetRow(for: snippet, context: context)
                    .id(PanelListItem.snippetItemID(snippet.id, context: context))
            }
        }
    }

    @ViewBuilder
    private func snippetRow(for item: PanelListItem, searchOrdinal: Int?) -> some View {
        if case .snippet(let match, let context) = item {
            SnippetRowView(
                snippet: match.snippet,
                tags: viewModel.tags(for: match.snippet),
                titleHighlights: match.titleHighlights,
                bodyHighlights: match.bodyHighlights,
                isTagColorShown: viewModel.preferences.isTagColorShown,
                isSelected: viewModel.isSnippetSelected(match.snippet.id, context: context),
                indexHint: viewModel.preferences.isNumberKeySelectionEnabled ? searchOrdinal : nil,
                onToggleFavorite: { viewModel.toggleFavorite(match.snippet.id) }
            )
            .onTapGesture { viewModel.selectSnippet(match.snippet) }
            .snippetContextMenu(match.snippet, onEdit: onOpenEditor, onDelete: onDeleteSnippet)
        }
    }

    private func snippetRow(for snippet: Snippet, context: String) -> some View {
        SnippetRowView(
            snippet: snippet,
            tags: viewModel.tags(for: snippet),
            titleHighlights: [],
            bodyHighlights: [],
            isTagColorShown: viewModel.preferences.isTagColorShown,
            isSelected: viewModel.isSnippetSelected(snippet.id, context: context),
            indexHint: nil,
            onToggleFavorite: { viewModel.toggleFavorite(snippet.id) }
        )
        .onTapGesture { viewModel.selectSnippet(snippet) }
        .snippetContextMenu(snippet, onEdit: onOpenEditor, onDelete: onDeleteSnippet)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(appFontSize.font(DesignTokens.Typography.sectionHeader, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    // MARK: - フッター

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(titleKey: "panel.footer.register", systemImage: "plus") { onOpenEditor(nil) }
            footerButton(titleKey: "panel.footer.list", systemImage: "list.bullet", action: onOpenList)
            Spacer()
            footerButton(titleKey: "panel.footer.settings", systemImage: "gearshape", action: onOpenSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func footerButton(titleKey: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.string(titleKey), systemImage: systemImage)
                .font(.system(size: 11))
        }
        .buttonStyle(PanelFooterButtonStyle())
        .foregroundStyle(.secondary)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

private extension View {
    func snippetContextMenu(
        _ snippet: Snippet,
        onEdit: @escaping (_ editingSnippetID: UUID?) -> Void,
        onDelete: @escaping (Snippet) -> Void
    ) -> some View {
        contextMenu {
            Button(L10n.string("panel.row.edit")) {
                onEdit(snippet.id)
            }
            Button(L10n.string("panel.row.delete"), role: .destructive) {
                onDelete(snippet)
            }
        }
    }
}
