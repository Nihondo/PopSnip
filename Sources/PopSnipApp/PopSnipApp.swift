// MARK: - PopSnipApp.swift
// アプリのエントリポイント。LSUIElement のメニューバー常駐アプリのため、
// SwiftUI の Scene は持たず（Settings シーンをプレースホルダとして使う）、
// 実体は AppDelegate → AppSharedState が管理する。

import AppKit
import SwiftUI

@main
struct PopSnipApp: App {
    @NSApplicationDelegateAdaptor(PopSnipAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class PopSnipAppDelegate: NSObject, NSApplicationDelegate {
    private var appSharedState: AppSharedState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appSharedState = AppSharedState()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
