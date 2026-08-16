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
            let tagSortOrderRawValue = userDefaults.string(forKey: UserDefaultsKeys.panelTagSortOrder),
            let tagSortOrder = TagSortOrder(rawValue: tagSortOrderRawValue)
        {
            preferences.tagSortOrder = tagSortOrder
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
        if
            let fontSizeRawValue = userDefaults.string(forKey: UserDefaultsKeys.panelFontSize),
            let fontSize = AppFontSize(rawValue: fontSizeRawValue)
        {
            preferences.fontSize = fontSize
        }

        // マイグレーション: コード上の defaultOrder に新しく追加されたセクション（例: .favorites）が、
        // 既に永続化済みの sectionOrder に含まれていない場合は末尾へ補い、有効セクションにも加える。
        // これにより、新しい PanelSection を追加しても、保存済み設定を持つ既存インストールで
        // 設定画面の選択肢から漏れ続けることを防ぐ。
        let missingSections = PanelSection.defaultOrder.filter { preferences.sectionOrder.contains($0) == false }
        if missingSections.isEmpty == false {
            preferences.sectionOrder.append(contentsOf: missingSections)
            preferences.enabledSections.formUnion(missingSections)
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
        userDefaults.set(preferences.tagSortOrder.rawValue, forKey: UserDefaultsKeys.panelTagSortOrder)
        userDefaults.set(preferences.presentationPosition.rawValue, forKey: UserDefaultsKeys.panelPresentationPosition)
        userDefaults.set(preferences.insertionStrategy.rawValue, forKey: UserDefaultsKeys.insertionStrategy)
        userDefaults.set(preferences.enterKeyBehavior.rawValue, forKey: UserDefaultsKeys.panelEnterKeyBehavior)
        userDefaults.set(
            preferences.isNumberKeySelectionEnabled,
            forKey: UserDefaultsKeys.panelIsNumberKeySelectionEnabled
        )
        userDefaults.set(preferences.isTagColorShown, forKey: UserDefaultsKeys.panelIsTagColorShown)
        userDefaults.set(preferences.clipboardRestoreDelayMs, forKey: UserDefaultsKeys.clipboardRestoreDelayMs)
        userDefaults.set(preferences.fontSize.rawValue, forKey: UserDefaultsKeys.panelFontSize)
    }

    // MARK: - パネルウインドウサイズ

    /// 検索パネルの直前のウインドウサイズ（幅・高さの両方をリサイズ・記憶できるようにするため）。
    /// 未保存の場合は nil を返し、呼び出し側で既定サイズにフォールバックする。
    public static func resolvePanelWindowSize(userDefaults: UserDefaults = .standard) -> CGSize? {
        guard
            userDefaults.object(forKey: UserDefaultsKeys.panelWindowWidth) != nil,
            userDefaults.object(forKey: UserDefaultsKeys.panelWindowHeight) != nil
        else {
            return nil
        }
        let width = userDefaults.double(forKey: UserDefaultsKeys.panelWindowWidth)
        let height = userDefaults.double(forKey: UserDefaultsKeys.panelWindowHeight)
        guard width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    public static func savePanelWindowSize(_ size: CGSize, userDefaults: UserDefaults = .standard) {
        userDefaults.set(Double(size.width), forKey: UserDefaultsKeys.panelWindowWidth)
        userDefaults.set(Double(size.height), forKey: UserDefaultsKeys.panelWindowHeight)
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
