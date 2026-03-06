// Uploader.swift
// 上传协调器：相机文件 → 云端存储 → 可选删除相机原文件
// 每个文件独立完成 下载→上传→删除 全流程

import Foundation
import ImageCaptureCore

@MainActor
@Observable
final class Uploader {

    // MARK: - State

    var isRunning  : Bool           = false
    var progress   : UploadProgress = UploadProgress()
    var history    : [UploadResult] = []
    var lastResult : UploadResult?

    weak var browser: CameraBrowser?

    // MARK: - Upload Entry Point

    func upload(items: [CameraItem], to account: StorageAccount) async {
        guard !items.isEmpty, let browser else { return }

        isRunning       = true
        progress        = UploadProgress()
        progress.filesTotal = items.count

        var result = UploadResult(account: account)

        for (index, item) in items.enumerated() {
            progress.currentFile = item.name
            progress.filesSent   = index
            item.isUploading     = true
            item.uploadProgress  = 0

            let t0 = Date()

            do {
                // 1. 下载到临时目录
                let localURL = try await browser.downloadToTemp(item)
                defer { try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent()) }

                // 2. 上传到云端
                let remotePath = buildRemotePath(account: account)
                let progressCB: @Sendable (Int64, Int64) -> Void = { [weak self] sent, total in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let elapsed = -t0.timeIntervalSinceNow
                        self.progress.bytesSent  = sent
                        self.progress.bytesTotal = total
                        self.progress.speed      = elapsed > 0 ? Double(sent) / elapsed : 0
                        self.progress.eta        = self.progress.speed > 0
                            ? Double(total - sent) / self.progress.speed : 0
                        item.uploadProgress = total > 0 ? Double(sent) / Double(total) : 0
                    }
                }

                switch account.type {
                case .webdav:
                    let svc = WebDAVService(account: account)
                    try await svc.upload(localURL: localURL, remotePath: remotePath, onProgress: progressCB)

                case .baiduPan:
                    let svc = BaiduPanService(account: account)
                    try await svc.upload(localURL: localURL, remotePath: remotePath, onProgress: progressCB)

                case .googleDrive:
                    let svc = GoogleDriveService(account: account)
                    // 根路径文件夹
                    let folderName = account.remotePath.trimmingCharacters(in: .init(charactersIn: "/"))
                    var folderID = try await svc.findOrCreateFolder(name: folderName.isEmpty ? "CamBridge" : folderName)
                    if account.createDateSubfolder {
                        folderID = try await svc.findOrCreateFolder(name: dateFolderName(), parentID: folderID)
                    }
                    try await svc.upload(localURL: localURL, folderID: folderID, onProgress: progressCB)
                }

                result.successCount += 1
                result.totalBytes   += item.fileSize
                item.isUploaded      = true

                // 3. 上传成功后删除相机文件
                if account.deleteAfterUpload {
                    browser.deleteItems([item])
                    result.deletedCount += 1
                }

            } catch {
                result.failedCount += 1
                result.failedItems.append((name: item.name, reason: error.localizedDescription))
            }

            item.isUploading    = false
            item.uploadProgress = 0
        }

        progress.filesSent = items.count
        result.endTime     = Date()
        lastResult         = result
        history.insert(result, at: 0)
        isRunning          = false
    }

    // MARK: - Helpers

    private func buildRemotePath(account: StorageAccount) -> String {
        var path = account.remotePath
        if account.createDateSubfolder {
            let sep = path.hasSuffix("/") ? "" : "/"
            path += "\(sep)\(dateFolderName())"
        }
        return path
    }

    private func dateFolderName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func cancelUpload() { isRunning = false }
}
