// MARK: - PanelShortcutConfiguration.swift
// ショートカット設定の永続化モデルと正規化ロジック。
// timeSlice/Sources/timeSliceApp/AppSettings.swift の CaptureNowShortcutConfiguration /
// CaptureNowShortcutResolver を、単一アクション専用から `PopSnipShortcutAction` 汎用へ一般化して移植。

import Carbon
import Foundation
import SwiftUI

/// 1アクション分のショートカット設定。
public struct PanelShortcutConfiguration: Equatable, Sendable {
    public let key: String
    public let modifiersRawValue: Int
    public let keyCode: Int?

    public init(key: String, modifiersRawValue: Int, keyCode: Int?) {
        self.key = key
        self.modifiersRawValue = modifiersRawValue
        self.keyCode = keyCode
    }

    public var eventModifiers: SwiftUI.EventModifiers {
        PanelShortcutResolver.resolveStoredEventModifiers(modifiersRawValue)
    }

    public var displayText: String {
        PanelShortcutResolver.makeDisplayText(key: key, modifiers: eventModifiers)
    }

    /// MVP 既定値: ⌥⌘Space。
    public static let defaultShowPanel = PanelShortcutConfiguration(
        key: "space",
        modifiersRawValue: Int(SwiftUI.EventModifiers([.command, .option]).rawValue),
        keyCode: kVK_Space
    )
}

/// ショートカット文字列の正規化・表示テキスト生成・UserDefaults 読み書きを担当する。
public enum PanelShortcutResolver {
    public static let allowedModifiers: SwiftUI.EventModifiers = [.command, .control, .option, .shift]

    /// UserDefaults から読み出した生値を `PanelShortcutConfiguration` へ解決する。
    public static func resolveConfiguration(
        shortcutKey: String,
        storedModifiersRawValue: Int,
        hasStoredModifiers: Bool,
        storedKeyCode: Int,
        hasStoredKeyCode: Bool
    ) -> PanelShortcutConfiguration? {
        let resolvedKeyCode = hasStoredKeyCode ? storedKeyCode : nil
        let normalizedKeyFromKeyCode = resolvedKeyCode.flatMap { resolveNormalizedKeyFromKeyCode($0) }
        let normalizedStoredKey = normalizeStoredKey(shortcutKey)
        guard let normalizedKey = normalizedKeyFromKeyCode ?? normalizedStoredKey else {
            return nil
        }
        let resolvedModifiersRawValue = resolveModifiersRawValue(
            storedModifiersRawValue: storedModifiersRawValue,
            hasStoredModifiers: hasStoredModifiers,
            hasShortcut: true
        )
        return PanelShortcutConfiguration(
            key: normalizedKey,
            modifiersRawValue: resolvedModifiersRawValue,
            keyCode: resolvedKeyCode
        )
    }

    public static func resolveStoredEventModifiers(_ modifiersRawValue: Int) -> SwiftUI.EventModifiers {
        SwiftUI.EventModifiers(rawValue: modifiersRawValue).intersection(allowedModifiers)
    }

    public static func makeDisplayText(key: String, modifiers: SwiftUI.EventModifiers) -> String {
        modifierSymbols(modifiers: modifiers) + displayKey(for: key)
    }

    public static func normalizeStoredKey(_ key: String) -> String? {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCharacter = trimmedKey.first, trimmedKey.count == 1 else {
            // "space" のような特殊キー名はそのまま許容する。
            return trimmedKey.isEmpty ? nil : trimmedKey.lowercased()
        }
        let normalizedKey = String(firstCharacter).lowercased()
        guard
            let scalar = normalizedKey.unicodeScalars.first,
            CharacterSet.controlCharacters.contains(scalar) == false
        else {
            return nil
        }
        return normalizedKey
    }

    public static func resolveNormalizedKeyFromKeyCode(_ keyCode: Int) -> String? {
        guard keyCode >= 0, keyCode <= Int(UInt16.max) else {
            return nil
        }
        if keyCode == kVK_Space {
            return "space"
        }
        guard let keyString = resolveKeyStringFromCurrentLayout(keyCode: UInt16(keyCode)) else {
            return nil
        }
        return normalizeStoredKey(keyString)
    }

    public static func resolveModifiersRawValue(
        storedModifiersRawValue: Int,
        hasStoredModifiers: Bool,
        hasShortcut: Bool
    ) -> Int {
        if hasStoredModifiers {
            return Int(resolveStoredEventModifiers(storedModifiersRawValue).rawValue)
        }
        if hasShortcut {
            return Int(SwiftUI.EventModifiers.command.rawValue)
        }
        return 0
    }

    private static func displayKey(for key: String) -> String {
        key == "space" ? "Space" : key.uppercased()
    }

    private static func modifierSymbols(modifiers: SwiftUI.EventModifiers) -> String {
        var symbols = ""
        if modifiers.contains(.control) {
            symbols += "⌃"
        }
        if modifiers.contains(.option) {
            symbols += "⌥"
        }
        if modifiers.contains(.shift) {
            symbols += "⇧"
        }
        if modifiers.contains(.command) {
            symbols += "⌘"
        }
        return symbols
    }

    private static func resolveKeyStringFromCurrentLayout(keyCode: UInt16) -> String? {
        guard
            let keyboardLayoutInputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let keyboardLayoutDataPointer = TISGetInputSourceProperty(
                keyboardLayoutInputSource,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }

        let keyboardLayoutData = unsafeBitCast(keyboardLayoutDataPointer, to: CFData.self)
        guard let keyboardLayoutDataBytes = CFDataGetBytePtr(keyboardLayoutData) else {
            return nil
        }
        let keyboardLayout = keyboardLayoutDataBytes.withMemoryRebound(
            to: UCKeyboardLayout.self,
            capacity: 1
        ) { $0 }

        var deadKeyState: UInt32 = 0
        var resolvedLength = 0
        var resolvedCharacters = [UniChar](repeating: 0, count: 4)

        let translationStatus = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            resolvedCharacters.count,
            &resolvedLength,
            &resolvedCharacters
        )
        guard translationStatus == noErr, resolvedLength > 0 else {
            return nil
        }
        return String(utf16CodeUnits: resolvedCharacters, count: resolvedLength)
    }

    // MARK: - UserDefaults 読み書き

    /// `action` に紐づくショートカット設定を UserDefaults から解決する。未設定・不正値の場合は
    /// `fallback`（既定値）を返す。
    public static func resolveConfiguration(
        for action: PopSnipShortcutAction,
        userDefaults: UserDefaults = .standard,
        fallback: PanelShortcutConfiguration?
    ) -> PanelShortcutConfiguration? {
        let keyDefaultsKey = UserDefaultsKeys.shortcutKey(action)
        let modifiersDefaultsKey = UserDefaultsKeys.shortcutModifiers(action)
        let keyCodeDefaultsKey = UserDefaultsKeys.shortcutKeyCode(action)

        guard userDefaults.object(forKey: keyDefaultsKey) != nil || userDefaults.object(forKey: keyCodeDefaultsKey) != nil else {
            return fallback
        }

        return resolveConfiguration(
            shortcutKey: userDefaults.string(forKey: keyDefaultsKey) ?? "",
            storedModifiersRawValue: userDefaults.integer(forKey: modifiersDefaultsKey),
            hasStoredModifiers: userDefaults.object(forKey: modifiersDefaultsKey) != nil,
            storedKeyCode: userDefaults.integer(forKey: keyCodeDefaultsKey),
            hasStoredKeyCode: userDefaults.object(forKey: keyCodeDefaultsKey) != nil
        ) ?? fallback
    }

    /// `configuration` を `action` に紐づけて UserDefaults へ保存する。
    public static func saveConfiguration(
        _ configuration: PanelShortcutConfiguration,
        for action: PopSnipShortcutAction,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(configuration.key, forKey: UserDefaultsKeys.shortcutKey(action))
        userDefaults.set(configuration.modifiersRawValue, forKey: UserDefaultsKeys.shortcutModifiers(action))
        if let keyCode = configuration.keyCode {
            userDefaults.set(keyCode, forKey: UserDefaultsKeys.shortcutKeyCode(action))
        } else {
            userDefaults.removeObject(forKey: UserDefaultsKeys.shortcutKeyCode(action))
        }
    }
}
