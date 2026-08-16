// MARK: - SnippetPanelPresenter.swift
// 検索パネルの表示・非表示・挿入実行を統括する。
// timeSlice/Sources/timeSliceApp/ManualCaptureCommentPanel.swift の
// ManualCaptureCommentPanelPresenter を移植したベースに、以下を差し替えている:
//   - panel.center() → マウスカーソル位置配置（画面端クランプ）
//   - NSApp.activate(ignoringOtherApps:) の呼び出しを削除
//     （styleMask に .nonactivatingPanel を含めることで前面アプリのフォーカスを保持するため）
//   - パネル表示直前に FocusSnapshotResolver で挿入先スナップショットを取得

import AppKit
import OSLog
import SwiftUI

@MainActor
final class SnippetPanelPresenter: NSObject, NSWindowDelegate {
    private let closeAnimationDuration: TimeInterval = 0.12
    private let store: SnippetStore

    private var activePanel: SnippetPanel?
    private var activeViewModel: SnippetPanelViewModel?
    private weak var searchField: NSTextField?
    private var keyDownEventMonitor: Any?
    private var currentTarget: InsertionTarget?
    private var isHandlingPanelAction = false

    /// 登録・一覧・設定ボタンが押されたときのハンドラ。AppSharedState 側から注入する。
    var onOpenEditor: ((_ target: InsertionTarget?) -> Void)?
    var onOpenList: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(store: SnippetStore) {
        self.store = store
    }

    var isPresenting: Bool {
        activePanel != nil
    }

    func toggle() {
        if isPresenting {
            dismissActivePanelIfNeeded()
        } else {
            present()
        }
    }

    func dismissActivePanelIfNeeded() {
        guard isPresenting else {
            return
        }
        closePanelIfNeeded(animated: true)
    }

    func present() {
        guard activePanel == nil else {
            return
        }
        guard AccessibilityPermission.isGranted() else {
            AccessibilityPermission.requestIfNeeded()
            return
        }
        guard let target = FocusSnapshotResolver.resolveCurrentTarget() else {
            Logger.panel.notice("前面アプリのフォーカス要素を取得できなかったためパネルを表示しません")
            return
        }
        currentTarget = target

        let preferences = AppSettingsResolver.resolvePanelPreferences()

        let panel = SnippetPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesignTokens.WindowSize.panelWidth, height: 1),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow

        let viewModel = SnippetPanelViewModel(
            store: store,
            preferences: preferences,
            onSelectSnippet: { [weak self] snippet in
                self?.insertAndClose(snippet)
            },
            onCancel: { [weak self] in
                self?.closePanelIfNeeded(animated: true)
            }
        )
        activeViewModel = viewModel

        let panelView = SnippetPanelView(
            store: store,
            viewModel: viewModel,
            onOpenEditor: { [weak self] in
                self?.openEditorAndClose()
            },
            onOpenList: { [weak self] in
                self?.performActionAndClose { self?.onOpenList?() }
            },
            onOpenSettings: { [weak self] in
                self?.performActionAndClose { self?.onOpenSettings?() }
            },
            onSearchFieldCreated: { [weak self] field in
                self?.searchField = field
            }
        )
        let hostingView = NSHostingView(rootView: panelView)
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        configurePanelShape(panel)

        activePanel = panel
        installKeyDownMonitorIfNeeded()

        position(panel, preferences: preferences)
        panel.makeKeyAndOrderFront(nil)
        configurePanelShape(panel)
        panel.invalidateShadow()
    }

    func windowWillClose(_ notification: Notification) {
        activePanel = nil
        activeViewModel = nil
        searchField = nil
        removeKeyDownMonitorIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isHandlingPanelAction == false else {
            return
        }
        closePanelIfNeeded(animated: true)
    }

    // MARK: - 挿入

    private func insertAndClose(_ snippet: Snippet) {
        guard let target = currentTarget else {
            closePanelIfNeeded(animated: false)
            return
        }
        let preferences = AppSettingsResolver.resolvePanelPreferences()
        isHandlingPanelAction = true
        closePanelIfNeeded(animated: false) { [weak self] in
            guard let self else {
                return
            }
            self.isHandlingPanelAction = false
            let result = SnippetInsertionService.insert(
                snippet.body,
                into: target,
                strategy: preferences.insertionStrategy,
                clipboardRestoreDelayMs: preferences.clipboardRestoreDelayMs
            )
            switch result {
            case .insertedViaAccessibility, .insertedViaClipboard:
                self.store.recordUsage(of: snippet.id)
            case .blockedBySecurity:
                Logger.panel.notice("パスワード欄と判定されたため挿入を中止しました")
            case .noFocusedTarget:
                Logger.panel.error("挿入先の UI 要素を解決できませんでした")
            }
            self.currentTarget = nil
        }
    }

    private func openEditorAndClose() {
        let target = currentTarget
        performActionAndClose { [weak self] in
            self?.onOpenEditor?(target)
        }
    }

    private func performActionAndClose(_ action: @escaping () -> Void) {
        isHandlingPanelAction = true
        closePanelIfNeeded(animated: true) { [weak self] in
            self?.isHandlingPanelAction = false
            self?.currentTarget = nil
            action()
        }
    }

    // MARK: - パネルのクローズ

    private func closePanelIfNeeded(animated: Bool, completion: (() -> Void)? = nil) {
        removeKeyDownMonitorIfNeeded()
        guard let activePanel else {
            completion?()
            return
        }
        self.activePanel = nil

        guard animated else {
            activePanel.close()
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = closeAnimationDuration
            activePanel.animator().alphaValue = 0
        } completionHandler: {
            activePanel.close()
            activePanel.alphaValue = 1
            completion?()
        }
    }

    // MARK: - キーモニタ
    //
    // Esc・上下矢印・Enter・Backspace・⌘1〜⌘9 をここで一元的に処理する。
    // 当初は上下矢印/Enter/Backspace を IMESafeSearchField 側の NSTextFieldDelegate の
    // doCommandBy 経由で判定していたが、単一行の NSTextField では field editor が
    // 上下矢印キーに対して doCommandBy を確実に発火させないケースがあり、検索結果の絞り込み中や
    // タグドリルダウン中にカーソルキーでの選択移動ができない不具合が残った。
    // そのため判定をここ（NSEvent ローカルモニタ）へ一本化し、`hasMarkedText` で
    // IME 変換中かどうかを確認したうえで、変換中は素通し（IME に処理させる）、
    // そうでなければアプリ側のキー操作として処理する。
    //
    // Cmd 修飾キーは IME の変換処理に一切関与しないため、⌘1〜⌘9 は常にここで処理してよい。

    private func installKeyDownMonitorIfNeeded() {
        guard keyDownEventMonitor == nil else {
            return
        }
        keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] keyEvent in
            guard let self, let activePanel = self.activePanel, activePanel.isKeyWindow else {
                return keyEvent
            }

            if
                keyEvent.modifierFlags.contains(.command),
                let character = keyEvent.charactersIgnoringModifiers?.first,
                let digit = character.wholeNumberValue,
                (1...9).contains(digit)
            {
                self.activeViewModel?.handleKeyEvent(.digit(digit))
                return nil
            }

            // IME 変換中（変換候補の選択中など）は、矢印・Enter・Backspace を
            // 入力システムにそのまま渡す（変換候補の操作を妨げない）。
            guard self.isComposingWithIME == false else {
                return keyEvent
            }

            switch keyEvent.keyCode {
            case 53: // Esc
                self.closePanelIfNeeded(animated: true)
                return nil
            case 126: // 上矢印
                self.activeViewModel?.handleKeyEvent(.arrowUp)
                return nil
            case 125: // 下矢印
                self.activeViewModel?.handleKeyEvent(.arrowDown)
                return nil
            case 36: // Enter / Return
                self.activeViewModel?.handleKeyEvent(.confirm)
                return nil
            case 51: // Backspace（Delete）
                if self.activeViewModel?.handleBackspaceForDrillDownIfNeeded() == true {
                    return nil
                }
                return keyEvent
            default:
                return keyEvent
            }
        }
    }

    /// 検索フィールドが現在 IME の変換（マークテキスト）状態かどうか。
    private var isComposingWithIME: Bool {
        (searchField?.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
    }

    private func removeKeyDownMonitorIfNeeded() {
        guard let keyDownEventMonitor else {
            return
        }
        NSEvent.removeMonitor(keyDownEventMonitor)
        self.keyDownEventMonitor = nil
    }

    // MARK: - 位置決め

    private func position(_ panel: NSPanel, preferences: PanelPreferences) {
        switch preferences.presentationPosition {
        case .screenCenter:
            panel.center()
        case .mouseLocation:
            positionAtMouseLocation(panel)
        }
    }

    private func positionAtMouseLocation(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = targetScreen?.visibleFrame else {
            panel.center()
            return
        }

        var origin = NSPoint(x: mouseLocation.x, y: mouseLocation.y - panel.frame.height)
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
    }

    // MARK: - 見た目

    private func configurePanelShape(_ panel: NSPanel) {
        guard let contentView = panel.contentView else {
            return
        }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.cornerRadius = DesignTokens.CornerRadius.panel
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true

        guard let frameView = contentView.superview else {
            return
        }
        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = NSColor.clear.cgColor
        frameView.layer?.cornerRadius = DesignTokens.CornerRadius.panel
        frameView.layer?.cornerCurve = .continuous
        frameView.layer?.masksToBounds = true
    }
}
