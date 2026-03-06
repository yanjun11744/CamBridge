// AccountsView.swift
// 网络存储账号管理（列表 + 添加 / 编辑表单）

import SwiftUI
import AppKit

// MARK: - Root

struct AccountsRootView: View {
    @Environment(AccountManager.self) private var mgr
    @State private var showAdd   = false
    @State private var editing   : StorageAccount?
    @State private var testMsg   : String?
    @State private var showTest  = false

    var body: some View {
        Group {
            if mgr.accounts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach($mgr.accounts) { $acc in
                        AccountRow(account: $acc,
                            onEdit:   { editing = acc },
                            onTest:   { testAccount(acc) },
                            onDelete: { mgr.delete(acc) }
                        )
                    }
                    .onMove(perform: mgr.move)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("网络存储账号")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("添加", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AccountFormView(account: nil) { mgr.add($0) }
        }
        .sheet(item: $editing) { acc in
            AccountFormView(account: acc) { mgr.update($0) }
        }
        .alert("连接测试", isPresented: $showTest) {
            Button("确定") {}
        } message: { Text(testMsg ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.plus").font(.system(size: 56)).foregroundStyle(.tertiary)
            Text("还没有网络存储").font(.title2).foregroundStyle(.secondary)
            Text("添加 WebDAV、百度网盘或 Google Drive，\n照片可直接从相机上传到云端，无需经过本地。")
                .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Label("添加存储账号", systemImage: "plus.circle.fill").font(.headline)
            }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func testAccount(_ acc: StorageAccount) {
        Task {
            testMsg  = await mgr.testWebDAV(acc)
            showTest = true
        }
    }
}

// MARK: - Account Row

struct AccountRow: View {
    @Binding var account: StorageAccount
    let onEdit  : () -> Void
    let onTest  : () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(account.type.tintColor.opacity(0.12)).frame(width: 42, height: 42)
                Image(systemName: account.type.sfSymbol).font(.system(size: 20)).foregroundStyle(account.type.tintColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name).font(.body.weight(.semibold))
                    Capsule().fill(account.type.tintColor.opacity(0.12))
                        .overlay { Text(account.type.rawValue).font(.caption).foregroundStyle(account.type.tintColor) }
                        .frame(width: 70, height: 18)
                }
                HStack(spacing: 6) {
                    if account.type == .webdav {
                        Text(account.webdavURL.isEmpty ? "未配置地址" : account.webdavURL)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(account.baiduAccessToken.isEmpty && account.googleAccessToken.isEmpty
                             ? "未授权" : "已授权").font(.caption).foregroundStyle(.secondary)
                    }
                    if account.deleteAfterUpload {
                        Text("· 上传后删除").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: $account.isEnabled).labelsHidden().controlSize(.small)
            Menu {
                Button("编辑", action: onEdit)
                if account.type == .webdav { Button("测试连接", action: onTest) }
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).frame(width: 28)
        }
        .padding(.vertical, 5)
        .opacity(account.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Account Form

struct AccountFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existing : StorageAccount?
    let onSave   : (StorageAccount) -> Void

    @State private var acc      : StorageAccount
    @State private var password : String = ""
    @State private var oauthCode: String = ""
    @State private var testing  : Bool   = false
    @State private var testOK   : Bool?

    init(account: StorageAccount?, onSave: @escaping (StorageAccount) -> Void) {
        self.existing = account
        self.onSave   = onSave
        _acc = State(initialValue: account ?? StorageAccount(name: "", type: .webdav))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Text(existing == nil ? "添加存储账号" : "编辑账号").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }.padding(20)
            Divider()

            // 表单
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    basicSection
                    switch acc.type {
                    case .webdav:      webdavSection
                    case .baiduPan:    baiduSection
                    case .googleDrive: googleSection
                    }
                    optionsSection
                }.padding(20)
            }

            Divider()

            // 底部按钮
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if acc.type == .webdav {
                    Button {
                        testing = true
                        Task {
                            var tmp = acc; tmp.webdavPassKey = "test_\(acc.id)"
                            KeychainHelper.save(password, forKey: tmp.webdavPassKey)
                            let svc = WebDAVService(account: tmp)
                            testOK = (try? await svc.testConnection()) != nil
                            testing = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if testing { ProgressView().controlSize(.small) }
                            else if let ok = testOK {
                                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(ok ? .green : .red)
                            }
                            Text("测试连接")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(acc.webdavURL.isEmpty || testing)
                }
                Button("保存") { save(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!valid)
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .frame(width: 520)
        .onAppear {
            if let e = existing { password = KeychainHelper.load(forKey: e.webdavPassKey) ?? "" }
        }
    }

    // MARK: - Sections

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("基本信息", systemImage: "info.circle").font(.headline)
            FormRow("名称") { TextField("如：家庭NAS", text: $acc.name).textFieldStyle(.roundedBorder) }
            FormRow("类型") {
                Picker("", selection: $acc.type) {
                    ForEach(ProviderType.allCases) { t in
                        Label(t.rawValue, systemImage: t.sfSymbol).tag(t)
                    }
                }.pickerStyle(.segmented)
            }
            HStack(spacing: 6) {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
                Text(acc.type.hint).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var webdavSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("服务器配置", systemImage: "server.rack").font(.headline)
            FormRow("地址") { TextField("https://nas.local:5006/dav", text: $acc.webdavURL).textFieldStyle(.roundedBorder) }
            FormRow("用户名") { TextField("账号", text: $acc.webdavUsername).textFieldStyle(.roundedBorder) }
            FormRow("密码") { SecureField("密码", text: $password).textFieldStyle(.roundedBorder) }
        }
    }

    private var baiduSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("百度网盘授权", systemImage: "cloud.fill").font(.headline)
            FormRow("App Key") { TextField("百度开放平台 App Key", text: $acc.baiduAppKey).textFieldStyle(.roundedBorder) }
            if acc.baiduAccessToken.isEmpty {
                oauthFlow(name: "百度网盘") {
                    if let url = URL(string: "https://openapi.baidu.com/oauth/2.0/authorize?response_type=code&client_id=\(acc.baiduAppKey)&redirect_uri=oob&scope=netdisk&display=popup") {
                        NSWorkspace.shared.open(url)
                    }
                } exchange: {
                    Task {
                        if let r = try? await BaiduPanService.exchangeToken(code: oauthCode) {
                            acc.baiduAccessToken  = r.access
                            acc.baiduRefreshToken = r.refresh
                            acc.baiduTokenExpiry  = Date().addingTimeInterval(TimeInterval(r.expIn))
                            oauthCode = ""
                        }
                    }
                }
            } else { authorizedBadge { acc.baiduAccessToken = ""; acc.baiduRefreshToken = "" } }
        }
    }

    private var googleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Google Drive 授权", systemImage: "externaldrive.connected.to.line.below.fill").font(.headline)
            FormRow("Client ID") { TextField("xxx.apps.googleusercontent.com", text: $acc.googleClientID).textFieldStyle(.roundedBorder) }
            FormRow("Client Secret") { SecureField("Client Secret", text: $acc.googleClientSecret).textFieldStyle(.roundedBorder) }
            if acc.googleAccessToken.isEmpty {
                oauthFlow(name: "Google Drive") {
                    if let url = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(acc.googleClientID)&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&scope=https://www.googleapis.com/auth/drive.file&access_type=offline&prompt=consent") {
                        NSWorkspace.shared.open(url)
                    }
                } exchange: {
                    Task {
                        if let r = try? await GoogleDriveService.exchangeToken(code: oauthCode) {
                            acc.googleAccessToken  = r.access
                            acc.googleRefreshToken = r.refresh
                            acc.googleTokenExpiry  = Date().addingTimeInterval(TimeInterval(r.expIn))
                            oauthCode = ""
                        }
                    }
                }
            } else { authorizedBadge { acc.googleAccessToken = ""; acc.googleRefreshToken = "" } }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("上传选项", systemImage: "gearshape").font(.headline).padding(.bottom, 12)
            FormRow("目标路径") { TextField("/相机导入", text: $acc.remotePath).textFieldStyle(.roundedBorder) }
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                Toggle(isOn: $acc.createDateSubfolder) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("按日期创建子文件夹")
                        Text("如 /相机导入/2025-12-25/").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12)
                Divider()
                Toggle(isOn: $acc.deleteAfterUpload) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text("上传成功后删除相机原文件")
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                        }
                        Text("逐张确认上传成功后删除，失败则保留。").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12)
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Reusable OAuth Flow

    @ViewBuilder
    private func oauthFlow(name: String, openBrowser: @escaping () -> Void, exchange: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text("需要通过 \(name) 授权后，本应用才能访问您的文件。")
                .font(.callout).foregroundStyle(.secondary)
            Button { openBrowser() } label: {
                Label("打开浏览器授权", systemImage: "safari")
            }.buttonStyle(.bordered)
            HStack {
                TextField("粘贴授权码…", text: $oauthCode).textFieldStyle(.roundedBorder)
                Button("确认") { exchange() }.disabled(oauthCode.isEmpty)
            }
        }
        .padding(14).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func authorizedBadge(onRevoke: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            Text("已成功授权").font(.headline)
            Spacer()
            Button("重新授权") { onRevoke() }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(12).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private var valid: Bool {
        guard !acc.name.isEmpty else { return false }
        switch acc.type {
        case .webdav:      return !acc.webdavURL.isEmpty && !acc.webdavUsername.isEmpty
        case .baiduPan:    return !acc.baiduAccessToken.isEmpty
        case .googleDrive: return !acc.googleAccessToken.isEmpty
        }
    }

    private func save() {
        if acc.type == .webdav {
            let k = "webdav_\(acc.id)"
            acc.webdavPassKey = k
            KeychainHelper.save(password, forKey: k)
        }
        onSave(acc)
    }
}

// MARK: - FormRow helper

struct FormRow<Content: View>: View {
    let label  : String
    let content: () -> Content
    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label; self.content = content
    }
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label).frame(width: 74, alignment: .trailing).foregroundStyle(.secondary).font(.callout)
            content()
        }
    }
}
