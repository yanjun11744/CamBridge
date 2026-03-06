// UploadSheet.swift
// 云端上传：选目标账号 + 实时进度 + 完成结果

import SwiftUI

struct UploadSheet: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(Uploader.self)       private var uploader
    @Environment(CameraBrowser.self)  private var browser
    @Environment(\.dismiss)           private var dismiss

    let items: [CameraItem]

    @State private var selectedID: UUID?
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("上传到网络存储").font(.title2.bold())
                    Text("已选 \(items.count) 个文件 · \(totalSizeText)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }.padding(20)

            Divider()

            if uploader.isRunning {
                UploadRunningView().environment(uploader).padding(24)
            } else if let result = uploader.lastResult, !showHistory {
                UploadResultView(result: result) { dismiss() }
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        accountPicker
                        filePreview
                    }.padding(20)
                }

                Divider()

                HStack {
                    Button("上传历史") { showHistory = true }
                        .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                    Spacer()
                    Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button { startUpload() } label: {
                        Label("开始上传", systemImage: "arrow.up.to.line.circle.fill").font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedID == nil)
                    .keyboardShortcut(.defaultAction)
                }.padding(20)
            }
        }
        .frame(width: 540)
        .onAppear { selectedID = accountManager.enabled.first?.id }
        .sheet(isPresented: $showHistory) {
            HistorySheet().environment(uploader)
        }
    }

    // MARK: - Account Picker

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("选择上传目标", systemImage: "externaldrive").font(.headline)

            if accountManager.enabled.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("暂无可用的网络存储账号，请先在账号管理中添加。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 2) {
                    ForEach(accountManager.enabled) { acc in
                        AccountPickRow(account: acc, selected: selectedID == acc.id) {
                            selectedID = acc.id
                        }
                    }
                }
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - File Preview

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("待上传文件（\(items.count)）", systemImage: "photo.stack").font(.headline)

            VStack(spacing: 0) {
                // 类型统计
                HStack(spacing: 20) {
                    typeTag(.photo); typeTag(.raw); typeTag(.video)
                    Spacer()
                }.padding(12)
                Divider()

                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { _, item in
                    HStack(spacing: 10) {
                        thumbIcon(item)
                        Text(item.name).font(.callout).lineLimit(1)
                        Spacer()
                        Text(item.formattedSize).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    Divider().padding(.leading, 58)
                }
                if items.count > 5 {
                    Text("以及 \(items.count - 5) 个其他文件…")
                        .font(.caption).foregroundStyle(.tertiary).padding(12)
                }
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            // 删除警告
            if let acc = selected, acc.deleteAfterUpload {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("已开启「上传后删除」：每张照片上传成功后将从相机中删除。")
                        .font(.caption).foregroundStyle(.orange)
                }
                .padding(10).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func typeTag(_ type: MediaType) -> some View {
        let n = items.filter { $0.mediaType == type }.count
        if n > 0 {
            Label("\(n) \(type.label)", systemImage: type.sfSymbol)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thumbIcon(_ item: CameraItem) -> some View {
        Group {
            if let t = item.thumbnail {
                Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.fill.secondary)
                    .overlay { Image(systemName: item.mediaType.sfSymbol).font(.caption).foregroundStyle(.tertiary) }
            }
        }
        .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private var selected: StorageAccount? {
        accountManager.accounts.first { $0.id == selectedID }
    }

    private var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.fileSize }, countStyle: .file)
    }

    private func startUpload() {
        guard let acc = selected else { return }
        Task { await uploader.upload(items: items, to: acc) }
    }
}

// MARK: - Account Pick Row

struct AccountPickRow: View {
    let account : StorageAccount
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.sfSymbol).frame(width: 24).foregroundStyle(account.type.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(account.type.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(account.remotePath).font(.caption).foregroundStyle(.tertiary)
                    if account.deleteAfterUpload {
                        Text("· 上传后删除").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.accent)
            } else {
                Circle().stroke(.tertiary, lineWidth: 1.5).frame(width: 20, height: 20)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(selected ? Color.accentColor.opacity(0.08) : .clear)
        .onTapGesture { onSelect() }
    }
}

// MARK: - Upload Running View

struct UploadRunningView: View {
    @Environment(Uploader.self) private var uploader

    var body: some View {
        let p = uploader.progress
        VStack(spacing: 22) {
            // 整体进度环
            ZStack {
                Circle().stroke(.fill.secondary, lineWidth: 8).frame(width: 96, height: 96)
                Circle().trim(from: 0, to: p.overallPercent)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 96, height: 96).rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: p.overallPercent)
                VStack(spacing: 1) {
                    Text("\(p.filesSent)").font(.title.bold().monospacedDigit())
                    Text("/ \(p.filesTotal)").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                Text("正在上传…").font(.headline)
                Text(p.currentFile).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                ProgressView(value: p.filePercent).tint(.accentColor).frame(maxWidth: 300)
                HStack(spacing: 16) {
                    Label(p.speedText, systemImage: "arrow.up").font(.caption).foregroundStyle(.secondary)
                    Label("剩余 \(p.etaText)", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { uploader.cancelUpload() } label: {
                Label("取消上传", systemImage: "stop.circle").foregroundStyle(.red)
            }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

// MARK: - Upload Result View

struct UploadResultView: View {
    let result   : UploadResult
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(result.failedCount == 0 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 76, height: 76)
                Image(systemName: result.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(result.failedCount == 0 ? Color.green : Color.orange)
            }
            Text(result.failedCount == 0 ? "上传完成 🎉" : "部分上传完成")
                .font(.title2.bold())
            HStack(spacing: 28) {
                StatPill("\(result.successCount)", "成功", .green)
                if result.failedCount > 0 { StatPill("\(result.failedCount)", "失败", .red) }
                if result.deletedCount > 0 { StatPill("\(result.deletedCount)", "已删除", .orange) }
                StatPill(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file), "总量", .blue)
                StatPill(result.durationText, "耗时", .secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

            if !result.failedItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("失败文件").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(result.failedItems.prefix(3), id: \.name) { f in
                        HStack {
                            Image(systemName: "xmark.circle").foregroundStyle(.red).font(.caption)
                            Text(f.name).font(.caption)
                            Spacer()
                            Text(f.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .padding(10).background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity)
            }

            Button("完成") { onDismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(28).frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct StatPill: View {
    let value: String; let label: String; let color: Color
    init(_ value: String, _ label: String, _ color: Color) {
        self.value = value; self.label = label; self.color = color
    }
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.callout.bold()).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Upload Status Bar (主界面悬浮条)

struct UploadStatusBar: View {
    @Environment(Uploader.self) private var uploader

    var body: some View {
        let p = uploader.progress
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.fill.secondary, lineWidth: 2.5).frame(width: 30, height: 30)
                Circle().trim(from: 0, to: p.overallPercent)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 30, height: 30).rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: p.overallPercent)
                Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold)).foregroundStyle(.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("上传中 · \(p.filesSent)/\(p.filesTotal)").font(.callout.weight(.medium))
                Text(p.currentFile).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(p.speedText).font(.caption).foregroundStyle(.secondary)
            Button { uploader.cancelUpload() } label: {
                Text("取消").foregroundStyle(.red)
            }.buttonStyle(.plain).font(.callout)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        .frame(maxWidth: 400)
    }
}

// MARK: - History Sheet

struct HistorySheet: View {
    @Environment(Uploader.self) private var uploader
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("上传历史").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
            }.padding(20)
            Divider()
            if uploader.history.isEmpty {
                CenterHint(icon: "clock.arrow.circlepath", text: "暂无上传记录")
            } else {
                List(uploader.history) { r in HistoryRow(result: r) }
                    .listStyle(.inset)
            }
        }
        .frame(width: 480, height: 460)
    }
}

struct HistoryRow: View {
    let result: UploadResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: result.account.type.sfSymbol).foregroundStyle(result.account.type.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.account.name).font(.headline)
                    Text(result.startTime, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(result.failedCount == 0 ? "成功" : "\(result.failedCount) 失败",
                      systemImage: result.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(result.failedCount == 0 ? .green : .orange)
            }
            HStack(spacing: 16) {
                StatPill("\(result.successCount)", "成功", .green)
                if result.deletedCount > 0 { StatPill("\(result.deletedCount)", "已删除", .orange) }
                StatPill(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file), "大小", .blue)
                StatPill(result.durationText, "耗时", .secondary)
            }
        }.padding(.vertical, 6)
    }
}
