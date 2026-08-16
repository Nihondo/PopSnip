// MARK: - UpdateSettingsView.swift
// Sparkle によるアップデート確認状態と設定を表示する設定タブ。
// timeSlice/Sources/timeSliceApp/Update/UpdateSettingsView.swift を移植。

import Foundation
import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject private var updateController = AppUpdateController.shared

    var body: some View {
        Form {
            Section {
                currentVersionRow
                lastCheckedRow
            }

            Section {
                checkNowButton
                automaticChecksToggle
            }
        }
        .formStyle(.grouped)
    }

    private var currentVersionRow: some View {
        LabeledContent(L10n.string("settings.update.currentVersion")) {
            Text(versionText)
                .foregroundStyle(.secondary)
        }
    }

    private var lastCheckedRow: some View {
        LabeledContent(L10n.string("settings.update.lastChecked")) {
            Text(lastCheckedText)
                .foregroundStyle(.secondary)
        }
    }

    private var checkNowButton: some View {
        Button(L10n.string("settings.update.checkNow")) {
            updateController.checkForUpdates()
        }
        .disabled(updateController.canCheckForUpdates == false)
    }

    private var automaticChecksToggle: some View {
        Toggle(
            L10n.string("settings.update.automaticChecks"),
            isOn: Binding(
                get: { updateController.automaticChecksEnabled },
                set: { updateController.setAutomaticChecksEnabled($0) }
            )
        )
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var lastCheckedText: String {
        guard let lastUpdateCheckDate = updateController.lastUpdateCheckDate else {
            return L10n.string("settings.update.lastChecked.never")
        }
        return lastUpdateCheckDate.formatted(date: .abbreviated, time: .shortened)
    }
}
