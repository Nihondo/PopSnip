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
    /// 確定した行のハイライトを見せてからパネルを閉じるまでの保持時間。
    private let confirmHighlightDuration: TimeInterval = 0.09
    private let store: SnippetStore

    private var activePanel: SnippetPanel?
    private var activeViewModel: SnippetPanelViewModel?
    private weak var searchField: NSTextField?
    private var keyDownEventMonitor: Any?
    private var currentTarget: InsertionTarget?
    private var isHandlingPanelAction = false

    /// 登録・一覧・設定ボタンが押されたときのハンドラ。AppSharedState 側から注入する。
    /// `editingSnippetID` は右クリックメニューからの編集時のみ非 nil（[[docs-macos-snippet-menu-app-plan]]）。
    var onOpenEditor: ((_ editingSnippetID: UUID?, _ target: InsertionTarget?) -> Void)?
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
        guard let target = FocusSnapshotResolver.resolveCurrentTarget(recovery: .immediate) else {
            Logger.panel.notice("前面アプリのフォーカス要素を取得できなかったためパネルを表示しません")
            return
        }
        currentTarget = target

        let preferences = AppSettingsResolver.resolvePanelPreferences()

        let panel = SnippetPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesignTokens.WindowSize.panelWidth, height: 1),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
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
            onSelectSnippet: { [weak self] snippet, waitsForConfirmHighlight in
                self?.insertAndClose(snippet, waitsForConfirmHighlight: waitsForConfirmHighlight)
            },
            onCancel: { [weak self] in
                self?.closePanelIfNeeded(animated: true)
            }
        )
        activeViewModel = viewModel

        let panelView = SnippetPanelView(
            store: store,
            viewModel: viewModel,
            onOpenEditor: { [weak self] editingSnippetID in
                self?.openEditorAndClose(editingSnippetID: editingSnippetID)
            },
            onOpenList: { [weak self] in
                self?.performActionAndClose { self?.onOpenList?() }
            },
            onOpenSettings: { [weak self] in
                self?.performActionAndClose { self?.onOpenSettings?() }
            },
            onDeleteSnippet: { [weak self] snippet in
                self?.confirmAndDeleteSnippet(snippet)
            },
            onSearchFieldCreated: { [weak self] field in
                self?.searchField = field
            }
        )
        let hostingView = NSHostingView(rootView: panelView.environment(\.appFontSize, preferences.fontSize))
        // fittingSize の評価と setContentSize は、hostingView を panel.contentView に
        // 代入する「前」に行う。SnippetPanelView は `.frame(minHeight: panelMinHeight)` を
        // 持つため、window に紐付いた状態で fittingSize/レイアウトパスが走ると、AppKit が
        // 一旦 minHeight（220pt）までウインドウを自動リサイズしてしまい、その拡大が
        // windowDidResize を発火させて直前に保存していたユーザーの希望サイズを
        // panelMinHeight で上書きしてしまう不具合があった（リサイズしても再現しない原因）。
        // contentView 未代入の状態なら fittingSize の評価が window に影響しないため、
        // 先にサイズを確定させてから contentView をセットする。
        let resolvedSize = resolvePanelContentSize(fittingSize: hostingView.fittingSize)
        panel.setContentSize(resolvedSize)
        panel.minSize = NSSize(
            width: DesignTokens.WindowSize.panelMinWidth,
            height: DesignTokens.WindowSize.panelMinHeight
        )
        panel.contentView = hostingView
        configurePanelShape(panel)

        activePanel = panel
        installKeyDownMonitorIfNeeded()

        position(panel, preferences: preferences)
        panel.makeKeyAndOrderFront(nil)
        configurePanelShape(panel)
        panel.invalidateShadow()
    }

    /// 直前に記憶したパネルサイズがあればそれを、無ければ内容がフィットするサイズを返す
    /// （UI_fix.md「メインUIのウィンドウサイズは可変にする（リサイズ結果を記憶する）」）。
    private func resolvePanelContentSize(fittingSize: NSSize) -> NSSize {
        guard let savedSize = AppSettingsResolver.resolvePanelWindowSize() else {
            return NSSize(
                width: DesignTokens.WindowSize.panelWidth,
                height: max(fittingSize.height, DesignTokens.WindowSize.panelDefaultHeight)
            )
        }
        return NSSize(
            width: max(savedSize.width, DesignTokens.WindowSize.panelMinWidth),
            height: max(savedSize.height, DesignTokens.WindowSize.panelMinHeight)
        )
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

    /// リサイズのたびにサイズを記憶する（UI_fix.md「リサイズ結果を記憶する」）。
    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else {
            return
        }
        AppSettingsResolver.savePanelWindowSize(panel.frame.size)
    }

    // MARK: - 挿入

    private func insertAndClose(_ snippet: Snippet, waitsForConfirmHighlight: Bool) {
        guard isHandlingPanelAction == false else {
            return
        }
        guard let target = currentTarget else {
            closePanelIfNeeded(animated: false)
            return
        }
        isHandlingPanelAction = true
        guard waitsForConfirmHighlight else {
            performInsertion(of: snippet, into: target)
            return
        }
        // 確定した行のハイライトが実際に描画されてから閉じる。保持中の誤操作を防ぐため
        // キーモニタを先に外しておく（closePanelIfNeeded 内でも呼ばれるため二重呼び出しは無害）。
        removeKeyDownMonitorIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmHighlightDuration) { [weak self] in
            MainActor.assumeIsolated {
                self?.performInsertion(of: snippet, into: target)
            }
        }
    }

    private func performInsertion(of snippet: Snippet, into target: InsertionTarget) {
        let preferences = AppSettingsResolver.resolvePanelPreferences()
        closePanelIfNeeded(animated: false) { [weak self] in
            guard let self else {
                return
            }
            self.isHandlingPanelAction = false
            // クリップボードを書き換える ClipboardInserter が走る前に {{clipboard}} の値を
            // 確定させる必要があるため、展開はここ（挿入直前）で行う。
            let context = PlaceholderContext.capture(from: target)
            let expanded = PlaceholderExpander.expand(snippet.body, context: context)
            let result = SnippetInsertionService.insert(
                expanded.text,
                into: target,
                strategy: preferences.insertionStrategy,
                clipboardRestoreDelayMs: preferences.clipboardRestoreDelayMs,
                caretUTF16Offset: expanded.caretUTF16Offset,
                caretCharacterOffsetFromEnd: expanded.caretCharacterOffsetFromEnd
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

    private func openEditorAndClose(editingSnippetID: UUID?) {
        let target = currentTarget
        performActionAndClose { [weak self] in
            self?.onOpenEditor?(editingSnippetID, target)
        }
    }

    /// スニペット行の右クリックメニューからの削除。パネルを閉じてからフォアグラウンドで
    /// 確認ダイアログを出す（パネルは `.nonactivatingPanel` のため、開いたままでは
    /// SwiftUI の `.alert` が安定して表示できない）。
    private func confirmAndDeleteSnippet(_ snippet: Snippet) {
        performActionAndClose { [weak self] in
            guard let self else {
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.string("panel.deleteConfirm.title")
            alert.informativeText = L10n.string("panel.deleteConfirm.message")
            let deleteButton = alert.addButton(withTitle: L10n.string("editor.button.delete"))
            deleteButton.hasDestructiveAction = true
            let cancelButton = alert.addButton(withTitle: L10n.string("editor.button.cancel"))
            cancelButton.keyEquivalent = "\u{1b}"
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
            self.store.deleteSnippet(id: snippet.id)
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

        // NSAnimationContext.runAnimationGroup の completionHandler は @escaping なため、
        // Swift 6 の厳格な並行性チェックでは @Sendable クロージャとして扱われる。実際には
        // AppKit がこのハンドラをメインスレッド上でのみ呼び出すことが保証されているが、
        // コンパイラはそれを静的に知らないため、以下の2点で明示的に安全性を主張する:
        //   1. completion クロージャは非 Sendable なため、nonisolated(unsafe) を付けた
        //      ローカル定数として捕捉する（SnippetPanel は MainActor 隔離クラスとして
        //      すでに Sendable 扱いのため、こちらには不要）
        //   2. ハンドラ本体は MainActor.assumeIsolated で実行し、MainActor 隔離のメンバ
        //      （close() / alphaValue）へ同期的にアクセスできるようにする
        let panelToClose = activePanel
        nonisolated(unsafe) let completionToRun = completion

        NSAnimationContext.runAnimationGroup { context in
            context.duration = closeAnimationDuration
            activePanel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panelToClose.close()
                panelToClose.alphaValue = 1
                completionToRun?()
            }
        }
    }

    // MARK: - キーモニタ
    //
    // Esc・矢印・Tab・Enter・Backspace・⌘1〜⌘9 をここで一元的に処理する。
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
                return self.activeViewModel?.handleKeyEvent(.digit(digit)) == true ? nil : keyEvent
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
                return self.activeViewModel?.handleKeyEvent(.arrowUp) == true ? nil : keyEvent
            case 125: // 下矢印
                return self.activeViewModel?.handleKeyEvent(.arrowDown) == true ? nil : keyEvent
            case 123: // 左矢印（タグ選択中のみ消費）
                return self.activeViewModel?.handleKeyEvent(.arrowLeft) == true ? nil : keyEvent
            case 124: // 右矢印（タグ選択中のみ消費）
                return self.activeViewModel?.handleKeyEvent(.arrowRight) == true ? nil : keyEvent
            case 48: // Tab / Shift+Tab（タグ選択中のみ消費）
                let event: PanelKeyEvent = keyEvent.modifierFlags.contains(.shift) ? .tabBackward : .tabForward
                return self.activeViewModel?.handleKeyEvent(event) == true ? nil : keyEvent
            case 36: // Enter / Return
                return self.activeViewModel?.handleKeyEvent(.confirm) == true ? nil : keyEvent
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
