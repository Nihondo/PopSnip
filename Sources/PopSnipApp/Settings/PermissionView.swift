// MARK: - PermissionView.swift
// Accessibility 権限の状態表示とシステム設定への誘導。

import AppKit
import SwiftUI

struct PermissionView: View {
    @State private var isGranted = AccessibilityPermission.isGranted()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            HStack(spacing: 8) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isGranted ? .green : .orange)
                Text(
                    isGranted
                        ? L10n.string("permission.status.granted")
                        : L10n.string("permission.status.notGranted")
                )
                .font(.headline)
            }

            Text(L10n.string("permission.description"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(L10n.string("permission.button.openSettings")) {
                    openAccessibilitySettings()
                }
                Button(L10n.string("permission.button.refresh")) {
                    isGranted = AccessibilityPermission.isGranted()
                }
            }
        }
        .padding(DesignTokens.Spacing.large)
        .onAppear {
            isGranted = AccessibilityPermission.isGranted()
        }
    }

    private func openAccessibilitySettings() {
        AccessibilityPermission.requestIfNeeded()
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
