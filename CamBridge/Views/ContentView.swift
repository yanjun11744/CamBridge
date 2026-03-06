// ContentView.swift
// 主界面：三栏布局（设备侧边栏 · 照片网格 · 详情面板）

import SwiftUI

struct ContentView: View {
    @Environment(CameraBrowser.self)  private var browser
    @Environment(AccountManager.self) private var accountManager
    @Environment(Uploader.self)       private var uploader

    @State private var selectedItemID   : UUID?
    @State private var showUploadSheet  : Bool = false
    @State private var showAccounts     : Bool = false
    @State private var showLocalResult  : Bool = false
    @State private var localResultURL   : [URL] = []
    @State private var columnVisibility : NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } content: {
            GridView(selectedItemID: $selectedItemID)
                .navigationSplitViewColumnWidth(min: 380, ideal: 580)
        } detail: {
            if let id = selectedItemID,
               let item = browser.mediaFiles.first(where: { $0.id == id }) {
                DetailView(item: item)
            } else {
                DetailPlaceholder()
            }
        }
        .toolbar { toolbarItems }
        // 上传到云端
        .sheet(isPresented: $showUploadSheet) {
            UploadSheet(items: browser.selectedItems)
                .environment(accountManager)
                .environment(uploader)
                .environment(browser)
        }
        // 网络存储管理
        .sheet(isPresented: $showAccounts) {
            NavigationStack {
                AccountsRootView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showAccounts = false }
                        }
                    }
            }
            .environment(accountManager)
            .frame(minWidth: 560, minHeight: 440)
        }
        // 上传状态悬浮条
        .overlay(alignment: .bottom) {
            if uploader.isRunning {
                UploadStatusBar()
                    .environment(uploader)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: uploader.isRunning)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // 全选 / 取消
            Button { browser.selectAll() } label: {
                Label("全选", systemImage: "checkmark.circle")
            }
            .disabled(browser.mediaFiles.isEmpty)

            Button { browser.deselectAll() } label: {
                Label("取消全选", systemImage: "circle")
            }
            .disabled(browser.selectedItems.isEmpty)

            Divider()

            // 本地导入
            Button {
                Task { await importToLocal() }
            } label: {
                Label("导入本地", systemImage: "square.and.arrow.down")
            }
            .disabled(browser.selectedItems.isEmpty)
            .help("将选中照片保存到 ~/Pictures/CamBridge/")

            // 云端上传（主操作）
            Button { showUploadSheet = true } label: {
                Label("上传到云端", systemImage: "arrow.up.to.line.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(browser.selectedItems.isEmpty || uploader.isRunning)
            .help("直接从相机上传到 WebDAV / 百度网盘 / Google Drive")

            Divider()

            // 账号管理
            Button { showAccounts = true } label: {
                Label("网络存储", systemImage: "externaldrive")
            }
            .help("管理网络存储账号")
        }
    }

    // MARK: - Local Import

    private func importToLocal() async {
        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/CamBridge/\(dateName())")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        var urls: [URL] = []
        for item in browser.selectedItems {
            if let url = try? await browser.downloadFile(item, to: dest) {
                urls.append(url)
                item.isUploaded = true
            }
        }
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    private func dateName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
}

// MARK: - Detail Placeholder

struct DetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("选择照片查看详情")
                .font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
