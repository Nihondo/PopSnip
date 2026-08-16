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

        let panelView = SnippetPanelView(
            store: store,
            preferences: preferences,
            onSelectSnippet: { [weak self] snippet in
                self?.insertAndClose(snippet)
            },
            onOpenEditor: { [weak self] in
                self?.openEditorAndClose()
            },
            onOpenList: { [weak self] in
                self?.performActionAndClose { self?.onOpenList?() }
            },
            onOpenSettings: { [weak self] in
                self?.performActionAndClose { self?.onOpenSettings?() }
            },
            onCancel: { [weak self] in
                self?.closePanelIfNeeded(animated: true)
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

    // MARK: - キーモニタ（Esc のみここで処理し、それ以外は SwiftUI 側の onKeyPress へ委譲する）

    private func installKeyDownMonitorIfNeeded() {
        guard keyDownEventMonitor == nil else {
            return
        }
        keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] keyEvent in
            guard let self, let activePanel = self.activePanel, activePanel.isKeyWindow else {
                return keyEvent
            }
            guard keyEvent.keyCode == 53 else { // Esc
                return keyEvent
            }
            self.closePanelIfNeeded(animated: true)
            return nil
        }
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
