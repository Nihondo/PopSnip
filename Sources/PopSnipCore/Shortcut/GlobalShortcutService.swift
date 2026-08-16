// MARK: - GlobalShortcutService.swift
// Carbon RegisterEventHotKey によるグローバルショートカット管理。
// timeSlice/Sources/timeSliceApp/AppStateSupport.swift の GlobalHotKeyManager を、
// 3種のホットキーを個別メソッドで持つ構造から `PopSnipShortcutAction` をキーとする
// 辞書ベースへ一般化して移植したもの。アクションを増やすときは
// `PopSnipShortcutAction` に case を足すだけで済む。

import Carbon
import Foundation

/// グローバルホットキーの登録・解除・ハンドラ配送を管理する。
@MainActor
public final class GlobalShortcutService {
    /// アクションが押されたときに呼ばれるハンドラ。
    public var handlers: [PopSnipShortcutAction: () -> Void] = [:]

    // Carbon のハンドル類は単なる不透明ポインタで、値そのものの読み書きはどのスレッドからでも安全。
    // deinit は MainActor から分離される（nonisolated）ため、ここでは `nonisolated(unsafe)` を付ける。
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private var registeredHotKeyRefs: [PopSnipShortcutAction: EventHotKeyRef] = [:]
    private var hotKeyIDsByAction: [PopSnipShortcutAction: EventHotKeyID] = [:]
    private var actionsByHotKeyID: [UInt32: PopSnipShortcutAction] = [:]
    private static let hotKeySignature: OSType = 0x504F_5053 // 'POPS'

    public init() {
        for (index, action) in PopSnipShortcutAction.allCases.enumerated() {
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: UInt32(index + 1))
            hotKeyIDsByAction[action] = hotKeyID
            actionsByHotKeyID[hotKeyID.id] = action
        }
        installHotKeyEventHandlerIfNeeded()
    }

    deinit {
        for hotKeyRef in registeredHotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// `action` のホットキー登録を更新する。`configuration` が nil の場合は解除のみ行う。
    public func register(_ action: PopSnipShortcutAction, configuration: PanelShortcutConfiguration?) {
        unregister(action)

        guard let configuration, let keyCode = configuration.keyCode, keyCode >= 0 else {
            return
        }
        guard let hotKeyID = hotKeyIDsByAction[action] else {
            return
        }

        let carbonModifiers = resolveCarbonModifiers(configuration.modifiersRawValue)
        var createdHotKeyRef: EventHotKeyRef?
        let registrationStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &createdHotKeyRef
        )
        guard registrationStatus == noErr, let createdHotKeyRef else {
            return
        }
        registeredHotKeyRefs[action] = createdHotKeyRef
    }

    /// `action` のホットキー登録を解除する。
    public func unregister(_ action: PopSnipShortcutAction) {
        guard let hotKeyRef = registeredHotKeyRefs[action] else {
            return
        }
        UnregisterEventHotKey(hotKeyRef)
        registeredHotKeyRefs[action] = nil
    }

    /// 解決済みの `EventHotKeyID`（signature/id とも Sendable な値型）を受け取り、対応するハンドラを呼ぶ。
    /// `eventRef`（生ポインタ、非 Sendable）を MainActor 側へ持ち込まないよう、
    /// イベントの解析は `resolveHotKeyID` 側（nonisolated なコールバック内）で済ませておく。
    fileprivate func dispatchHandler(for hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == Self.hotKeySignature, let action = actionsByHotKeyID[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        handlers[action]?()
        return noErr
    }

    private func installHotKeyEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }
        var hotKeyPressedEventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            popSnipGlobalHotKeyEventHandler,
            1,
            &hotKeyPressedEventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    private func resolveCarbonModifiers(_ shortcutModifiersRawValue: Int) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        if shortcutModifiersRawValue & 16 != 0 {
            carbonModifiers |= UInt32(cmdKey)
        }
        if shortcutModifiersRawValue & 8 != 0 {
            carbonModifiers |= UInt32(optionKey)
        }
        if shortcutModifiersRawValue & 4 != 0 {
            carbonModifiers |= UInt32(controlKey)
        }
        if shortcutModifiersRawValue & 2 != 0 {
            carbonModifiers |= UInt32(shiftKey)
        }
        return carbonModifiers
    }
}

private func popSnipGlobalHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ eventRef: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let eventRef else {
        return OSStatus(eventNotHandledErr)
    }

    // eventRef（生ポインタ、非 Sendable）はここで読み切り、Sendable な EventHotKeyID だけを
    // MainActor 側へ渡す。
    var pressedHotKeyID = EventHotKeyID()
    let parameterStatus = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedHotKeyID
    )
    guard parameterStatus == noErr else {
        return OSStatus(eventNotHandledErr)
    }

    let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        service.dispatchHandler(for: pressedHotKeyID)
    }
}
