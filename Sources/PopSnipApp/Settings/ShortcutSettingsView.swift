// MARK: - ShortcutSettingsView.swift
// ショートカット設定。PopSnipShortcutAction.allCases を列挙して、
// timeSlice の CaptureNowShortcutRecorderView を移植した記録 UI を配置する。
// アクションを増やすときは PopSnipShortcutAction に case を足すだけでこの画面にも反映される。

import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    let shortcutService: GlobalShortcutService

    @State private var configurations: [PopSnipShortcutAction: PanelShortcutConfiguration] = [:]

    var body: some View {
        Form {
            ForEach(PopSnipShortcutAction.allCases, id: \.self) { action in
                Section(L10n.string(action.localizationKey)) {
                    PanelShortcutRecorderView(
                        shortcutDisplayText: configurations[action]?.displayText ?? L10n.string("settings.shortcut.unassigned"),
                        hasShortcut: configurations[action] != nil,
                        onShortcutCaptured: { key, keyCode, modifiers in
                            let configuration = PanelShortcutConfiguration(
                                key: key,
                                modifiersRawValue: Int(modifiers.rawValue),
                                keyCode: keyCode
                            )
                            apply(configuration, for: action)
                        },
                        onShortcutCleared: {
                            clear(action)
                        }
                    )
                    if action != .showPanel {
                        Text(L10n.string("settings.shortcut.reservedForFutureUse"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.large)
        .onAppear(perform: loadConfigurations)
    }

    private func loadConfigurations() {
        for action in PopSnipShortcutAction.allCases {
            configurations[action] = AppSettingsResolver.resolveShortcutConfiguration(for: action)
        }
    }

    private func apply(_ configuration: PanelShortcutConfiguration, for action: PopSnipShortcutAction) {
        configurations[action] = configuration
        PanelShortcutResolver.saveConfiguration(configuration, for: action)
        if PopSnipShortcutAction.activeInMVP.contains(action) {
            shortcutService.register(action, configuration: configuration)
        }
    }

    private func clear(_ action: PopSnipShortcutAction) {
        configurations[action] = nil
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.shortcutKey(action))
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.shortcutModifiers(action))
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.shortcutKeyCode(action))
        shortcutService.unregister(action)
    }
}

/// ショートカット記録用のボタン。
/// timeSlice/Sources/timeSliceApp/SettingsComponents.swift の CaptureNowShortcutRecorderView を移植。
struct PanelShortcutRecorderView: View {
    let shortcutDisplayText: String
    let hasShortcut: Bool
    let onShortcutCaptured: (String, Int, EventModifiers) -> Void
    let onShortcutCleared: () -> Void

    @State private var isRecordingShortcut = false
    @State private var keyEventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecordingShortcut ? L10n.string("settings.shortcut.recording") : shortcutDisplayText) {
                isRecordingShortcut = true
            }
            .buttonStyle(.bordered)

            if hasShortcut {
                Button(L10n.string("settings.shortcut.clear")) {
                    onShortcutCleared()
                }
                .buttonStyle(.bordered)
                .disabled(isRecordingShortcut)
            }
        }
        .onChange(of: isRecordingShortcut) { _, isRecording in
            if isRecording {
                startKeyEventMonitor()
            } else {
                stopKeyEventMonitor()
            }
        }
        .onDisappear {
            stopKeyEventMonitor()
        }
    }

    private func startKeyEventMonitor() {
        guard keyEventMonitor == nil else {
            return
        }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingShortcut else {
                return event
            }
            return handleKeyDownEvent(event)
        }
    }

    private func stopKeyEventMonitor() {
        guard let keyEventMonitor else {
            return
        }
        NSEvent.removeMonitor(keyEventMonitor)
        self.keyEventMonitor = nil
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Esc: 記録キャンセル
            isRecordingShortcut = false
            return nil
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete: クリア
            onShortcutCleared()
            isRecordingShortcut = false
            return nil
        }

        guard let capturedKey = resolveCapturedKey(event: event) else {
            NSSound.beep()
            return nil
        }
        let capturedModifiers = resolveCapturedModifiers(eventModifierFlags: event.modifierFlags)
        guard capturedModifiers.isEmpty == false else {
            NSSound.beep()
            return nil
        }

        onShortcutCaptured(capturedKey, Int(event.keyCode), capturedModifiers)
        isRecordingShortcut = false
        return nil
    }

    private func resolveCapturedModifiers(eventModifierFlags: NSEvent.ModifierFlags) -> EventModifiers {
        var capturedModifiers: EventModifiers = []
        if eventModifierFlags.contains(.command) {
            capturedModifiers.insert(.command)
        }
        if eventModifierFlags.contains(.control) {
            capturedModifiers.insert(.control)
        }
        if eventModifierFlags.contains(.option) {
            capturedModifiers.insert(.option)
        }
        if eventModifierFlags.contains(.shift) {
            capturedModifiers.insert(.shift)
        }
        return capturedModifiers
    }

    private func resolveCapturedKey(event: NSEvent) -> String? {
        PanelShortcutResolver.resolveNormalizedKeyFromKeyCode(Int(event.keyCode))
    }
}
