// MARK: - GeneralSettingsView.swift
// 一般設定: ログイン時起動、挿入方式、クリップボード復元待機時間、スニペットファイルパス。
// 設定変更は即時反映する（AppSettingsResolver 経由で UserDefaults へ保存）。

import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var store: SnippetStore

    @State private var isLaunchAtLoginEnabled = LaunchAtLoginManager.resolveRegistrationState()
    @State private var launchAtLoginErrorMessage: String?
    @State private var preferences = AppSettingsResolver.resolvePanelPreferences()

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("settings.general.launchAtLogin"), isOn: $isLaunchAtLoginEnabled)
                    .onChange(of: isLaunchAtLoginEnabled, updateLaunchAtLogin)
                if let launchAtLoginErrorMessage {
                    Text(launchAtLoginErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(L10n.string("settings.general.insertion")) {
                Picker(L10n.string("settings.general.insertionStrategy"), selection: $preferences.insertionStrategy) {
                    Text(L10n.string("settings.general.insertionStrategy.automatic")).tag(InsertionStrategy.automatic)
                    Text(L10n.string("settings.general.insertionStrategy.accessibilityOnly"))
                        .tag(InsertionStrategy.accessibilityOnly)
                    Text(L10n.string("settings.general.insertionStrategy.clipboardOnly")).tag(InsertionStrategy.clipboardOnly)
                }
                .onChange(of: preferences.insertionStrategy) { savePreferences() }

                Stepper(
                    L10n.format("settings.general.clipboardRestoreDelay", preferences.clipboardRestoreDelayMs),
                    value: $preferences.clipboardRestoreDelayMs,
                    in: 0...ClipboardInserter.maxRestoreDelayMs,
                    step: 20
                )
                .onChange(of: preferences.clipboardRestoreDelayMs) { savePreferences() }
            }

            Section(L10n.string("settings.general.storage")) {
                HStack {
                    Text(store.fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L10n.string("settings.general.revealInFinder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.large)
    }

    private func updateLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.updateRegistration(isEnabled: isLaunchAtLoginEnabled)
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginErrorMessage = error.localizedDescription
            isLaunchAtLoginEnabled = LaunchAtLoginManager.resolveRegistrationState()
        }
    }

    private func savePreferences() {
        AppSettingsResolver.savePanelPreferences(preferences)
    }
}
