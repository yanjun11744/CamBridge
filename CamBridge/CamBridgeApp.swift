//
//  CamBridgeApp.swift
//  CamBridge
//
//  Created by Yanjun Sun on 2026/3/6.
//

// CamBridgeApp.swift
// Xcode 26 · Swift 6.2 · SwiftUI · macOS 15+

import SwiftUI

@main
struct CamBridgeApp: App {

    @State private var browser        = CameraBrowser()
    @State private var accountManager = AccountManager()
    @State private var uploader       = Uploader()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(browser)
                .environment(accountManager)
                .environment(uploader)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { uploader.browser = browser }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("设备") {
                Button("刷新设备") { browser.startBrowsing() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        // 独立的网络存储管理窗口
        Window("网络存储账号", id: "accounts") {
            AccountsRootView()
                .environment(accountManager)
                .frame(minWidth: 560, minHeight: 440)
        }
    }
}
