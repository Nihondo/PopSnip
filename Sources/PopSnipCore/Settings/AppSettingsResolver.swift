// MARK: - AppSettingsResolver.swift
// UserDefaults の生値を型付き設定へ解決する。timeSlice の AppSettingsResolver と同じ役割。
// View / Service はここを経由してのみ設定値を読み書きする。

import Foundation

/// UserDefaults ⇔ 型付き設定モデルの変換を担当する。
public enum AppSettingsResolver {
    // MARK: - パネル表示設定

    public static func resolvePanelPreferences(userDefaults: UserDefaults = .standard) -> PanelPreferences {
        var preferences = PanelPreferences.default

        if let orderRawValues = userDefaults.array(forKey: UserDefaultsKeys.panelSectionOrder) as? [String] {
            let resolvedOrder = orderRawValues.compactMap(PanelSection.init(rawValue:))
            if resolvedOrder.isEmpty == false {
                preferences.sectionOrder = resolvedOrder
            }
        }

        if let enabledRawValues = userDefaults.array(forKey: UserDefaultsKeys.panelEnabledSections) as? [String] {
            preferences.enabledSections = Set(enabledRawValues.compactMap(PanelSection.init(rawValue:)))
        }

        if userDefaults.object(forKey: UserDefaultsKeys.panelRecentsLimit) != nil {
            preferences.recentsLimit = userDefaults.integer(forKey: UserDefaultsKeys.panelRecentsLimit)
        }
        if userDefaults.object(forKey: UserDefaultsKeys.panelSearchResultLimit) != nil {
            preferences.searchResultLimit = userDefaults.integer(forKey: UserDefaultsKeys.panelSearchResultLimit)
        }
        if
            let sortOrderRawValue = userDefaults.string(forKey: UserDefaultsKeys.panelSearchSortOrder),
            let sortOrder = SearchSortOrder(rawValue: sortOrderRawValue)
        {
            preferences.searchSortOrder = sortOrder
        }
        if
            let positionRawValue = userDefaults.string(forKey: UserDefaultsKeys.panelPresentationPosition),
            let position = PanelPosition(rawValue: positionRawValue)
        {
            preferences.presentationPosition = position
        }
        if
            let strategyRawValue = userDefaults.string(forKey: UserDefaultsKeys.insertionStrategy),
            let strategy = InsertionStrategy(rawValue: strategyRawValue)
        {
            preferences.insertionStrategy = strategy
        }
        if
            let behaviorRawValue = userDefaults.string(forKey: UserDefaultsKeys.panelEnterKeyBehavior),
            let behavior = EnterKeyBehavior(rawValue: behaviorRawValue)
        {
            preferences.enterKeyBehavior = behavior
        }
        if userDefaults.object(forKey: UserDefaultsKeys.panelIsNumberKeySelectionEnabled) != nil {
            preferences.isNumberKeySelectionEnabled = userDefaults.bool(
                forKey: UserDefaultsKeys.panelIsNumberKeySelectionEnabled
            )
        }
        if userDefaults.object(forKey: UserDefaultsKeys.panelIsTagColorShown) != nil {
            preferences.isTagColorShown = userDefaults.bool(forKey: UserDefaultsKeys.panelIsTagColorShown)
        }
        if userDefaults.object(forKey: UserDefaultsKeys.clipboardRestoreDelayMs) != nil {
            preferences.clipboardRestoreDelayMs = userDefaults.integer(forKey: UserDefaultsKeys.clipboardRestoreDelayMs)
        }

        return preferences
    }

    public static func savePanelPreferences(_ preferences: PanelPreferences, userDefaults: UserDefaults = .standard) {
        userDefaults.set(preferences.sectionOrder.map(\.rawValue), forKey: UserDefaultsKeys.panelSectionOrder)
        userDefaults.set(
            preferences.enabledSections.map(\.rawValue),
            forKey: UserDefaultsKeys.panelEnabledSections
        )
        userDefaults.set(preferences.recentsLimit, forKey: UserDefaultsKeys.panelRecentsLimit)
        userDefaults.set(preferences.searchResultLimit, forKey: UserDefaultsKeys.panelSearchResultLimit)
        userDefaults.set(preferences.searchSortOrder.rawValue, forKey: UserDefaultsKeys.panelSearchSortOrder)
        userDefaults.set(preferences.presentationPosition.rawValue, forKey: UserDefaultsKeys.panelPresentationPosition)
        userDefaults.set(preferences.insertionStrategy.rawValue, forKey: UserDefaultsKeys.insertionStrategy)
        userDefaults.set(preferences.enterKeyBehavior.rawValue, forKey: UserDefaultsKeys.panelEnterKeyBehavior)
        userDefaults.set(
            preferences.isNumberKeySelectionEnabled,
            forKey: UserDefaultsKeys.panelIsNumberKeySelectionEnabled
        )
        userDefaults.set(preferences.isTagColorShown, forKey: UserDefaultsKeys.panelIsTagColorShown)
        userDefaults.set(preferences.clipboardRestoreDelayMs, forKey: UserDefaultsKeys.clipboardRestoreDelayMs)
    }

    // MARK: - ショートカット

    public static func resolveShortcutConfiguration(
        for action: PopSnipShortcutAction,
        userDefaults: UserDefaults = .standard
    ) -> PanelShortcutConfiguration? {
        let fallback: PanelShortcutConfiguration? = action == .showPanel ? .defaultShowPanel : nil
        return PanelShortcutResolver.resolveConfiguration(
            for: action,
            userDefaults: userDefaults,
            fallback: fallback
        )
    }

    // MARK: - 一般設定

    public static func resolveLaunchAtLoginEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: UserDefaultsKeys.launchAtLoginEnabled)
    }

    public static func resolveSnippetFilePath(userDefaults: UserDefaults = .standard) -> String? {
        userDefaults.string(forKey: UserDefaultsKeys.snippetFilePath)
    }
}
