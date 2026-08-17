// MARK: - PanelLayoutSettingsView.swift
// パネル表示設定: セクションのドラッグ並び替え・表示ON/OFF、件数、並び順、表示位置など。
// ここで編集する PanelPreferences は Phase 2〜4 で先に用意した構造にそのまま被さる
// （[[docs-macos-snippet-menu-app-plan]] の設定駆動方針）。

import SwiftUI

struct PanelLayoutSettingsView: View {
    @State private var preferences = AppSettingsResolver.resolvePanelPreferences()

    var body: some View {
        Form {
            Section(L10n.string("settings.panel.sections")) {
                List {
                    ForEach(preferences.sectionOrder) { section in
                        Toggle(isOn: bindingForSectionEnabled(section)) {
                            Text(L10n.string(section.localizationKey))
                        }
                    }
                    .onMove(perform: moveSections)
                }
                .frame(minHeight: 120)
            }

            Section(L10n.string("settings.panel.counts")) {
                Stepper(
                    L10n.format("settings.panel.recentsLimit", preferences.recentsLimit),
                    value: $preferences.recentsLimit,
                    in: 1...30
                )
                .onChange(of: preferences.recentsLimit) { savePreferences() }

                Stepper(
                    L10n.format("settings.panel.searchResultLimit", preferences.searchResultLimit),
                    value: $preferences.searchResultLimit,
                    in: 5...50
                )
                .onChange(of: preferences.searchResultLimit) { savePreferences() }
            }

            Section(L10n.string("settings.panel.behavior")) {
                Picker(L10n.string("settings.panel.searchSortOrder"), selection: $preferences.searchSortOrder) {
                    Text(L10n.string("settings.panel.searchSortOrder.relevance")).tag(SearchSortOrder.relevance)
                    Text(L10n.string("settings.panel.searchSortOrder.usageCount")).tag(SearchSortOrder.usageCount)
                    Text(L10n.string("settings.panel.searchSortOrder.updatedAt")).tag(SearchSortOrder.updatedAt)
                }
                .onChange(of: preferences.searchSortOrder) { savePreferences() }

                Picker(L10n.string("settings.panel.tagSortOrder"), selection: $preferences.tagSortOrder) {
                    Text(L10n.string("settings.panel.tagSortOrder.registrationOrder")).tag(TagSortOrder.registrationOrder)
                    Text(L10n.string("settings.panel.tagSortOrder.snippetCountDescending")).tag(TagSortOrder.snippetCountDescending)
                }
                .onChange(of: preferences.tagSortOrder) { savePreferences() }

                Picker(L10n.string("settings.panel.tagLayoutStyle"), selection: $preferences.tagLayoutStyle) {
                    Text(L10n.string("settings.panel.tagLayoutStyle.horizontalStrip"))
                        .tag(TagLayoutStyle.horizontalStrip)
                    Text(L10n.string("settings.panel.tagLayoutStyle.verticalList"))
                        .tag(TagLayoutStyle.verticalList)
                }
                .onChange(of: preferences.tagLayoutStyle) { savePreferences() }

                Picker(L10n.string("settings.panel.presentationPosition"), selection: $preferences.presentationPosition) {
                    Text(L10n.string("settings.panel.presentationPosition.mouse")).tag(PanelPosition.mouseLocation)
                    Text(L10n.string("settings.panel.presentationPosition.center")).tag(PanelPosition.screenCenter)
                }
                .onChange(of: preferences.presentationPosition) { savePreferences() }

                Picker(L10n.string("settings.panel.enterKeyBehavior"), selection: $preferences.enterKeyBehavior) {
                    Text(L10n.string("settings.panel.enterKeyBehavior.insert")).tag(EnterKeyBehavior.insert)
                    Text(L10n.string("settings.panel.enterKeyBehavior.copyOnly")).tag(EnterKeyBehavior.copyOnly)
                }
                .onChange(of: preferences.enterKeyBehavior) { savePreferences() }

                Toggle(
                    L10n.string("settings.panel.numberKeySelection"),
                    isOn: $preferences.isNumberKeySelectionEnabled
                )
                .onChange(of: preferences.isNumberKeySelectionEnabled) { savePreferences() }

                Toggle(L10n.string("settings.panel.tagColor"), isOn: $preferences.isTagColorShown)
                    .onChange(of: preferences.isTagColorShown) { savePreferences() }
            }
        }
        .formStyle(.grouped)
    }

    private func bindingForSectionEnabled(_ section: PanelSection) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledSections.contains(section) },
            set: { isEnabled in
                if isEnabled {
                    preferences.enabledSections.insert(section)
                } else {
                    preferences.enabledSections.remove(section)
                }
                savePreferences()
            }
        )
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        preferences.sectionOrder.move(fromOffsets: source, toOffset: destination)
        savePreferences()
    }

    private func savePreferences() {
        AppSettingsResolver.savePanelPreferences(preferences)
    }
}
