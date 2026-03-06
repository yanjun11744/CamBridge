// CameraBrowser.swift
// MTP/PTP 设备浏览与文件管理
// 修复了所有 Swift 6 并发 + ImageCaptureCore 新 API 编译错误

import Foundation
import ImageCaptureCore
import SwiftUI

@MainActor
@Observable
final class CameraBrowser: NSObject {

    // MARK: - Observable State

    var devices       : [ICCameraDevice] = []
    var selectedDevice: ICCameraDevice?
    var mediaFiles    : [CameraItem]     = []
    var isLoading     : Bool             = false
    var errorMessage  : String?

    // MARK: - Private
    // 修复1: nonisolated(unsafe) 允许 deinit 访问，同时保持 @MainActor 整体隔离
    nonisolated(unsafe) private var browser: ICDeviceBrowser?

    // MARK: - Init / Deinit

    override init() {
        super.init()
        startBrowsing()
    }

    deinit {
        // deinit 是 nonisolated，用 nonisolated(unsafe) 安全访问
        browser?.stop()
        browser?.delegate = nil
    }

    // MARK: - Browsing

    func startBrowsing() {
        browser?.stop()
        let b = ICDeviceBrowser()
        b.delegate  = self
        b.browsedDeviceTypeMask = ICDeviceTypeMask.camera
        b.start()
        browser = b
    }

    func stopBrowsing() {
        browser?.stop()
        browser?.delegate = nil
        browser = nil
    }

    // MARK: - Device

    func selectDevice(_ device: ICCameraDevice) {
        selectedDevice?.requestCloseSession()
        selectedDevice = device
        mediaFiles     = []
        isLoading      = true
        device.delegate = self
        device.requestOpenSession()
    }

    // MARK: - File Operations

    func requestThumbnail(for item: CameraItem) {
        item.file.requestThumbnail()
    }

    /// 下载到临时目录，返回本地 URL（供上传服务使用）
    func downloadToTemp(_ item: CameraItem) async throws -> URL {
        guard let device = selectedDevice else {
            throw CamError.noDevice
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return try await withCheckedThrowingContinuation { cont in
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: dir,
                .saveAsFilename:        item.name,
                .overwrite:             true
            ]
            let helper = DownloadHelper(file: item.file, dir: dir, cont: cont)
            device.requestDownloadFile(
                item.file,
                options: options,
                downloadDelegate: helper,
                didDownloadSelector: #selector(DownloadHelper.done(_:error:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    /// 下载到指定目录（本地导入用）
    func downloadFile(_ item: CameraItem, to directory: URL) async throws -> URL {
        guard let device = selectedDevice else { throw CamError.noDevice }

        return try await withCheckedThrowingContinuation { cont in
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: directory,
                .saveAsFilename:        item.name,
                .overwrite:             true
            ]
            let helper = DownloadHelper(file: item.file, dir: directory, cont: cont)
            device.requestDownloadFile(
                item.file,
                options: options,
                downloadDelegate: helper,
                didDownloadSelector: #selector(DownloadHelper.done(_:error:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    // 修复2: requestDeleteFiles 新签名 — completion 只有 [ICDeleteError: ICCameraItem]，无 Error 参数
    func deleteItems(_ items: [CameraItem]) {
        let files = items.map(\.file)
        selectedDevice?.requestDeleteFiles(files) { [weak self] errorDict in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !errorDict.isEmpty {
                    self.errorMessage = "部分文件删除失败（\(errorDict.count) 项）"
                }
                // 从列表中移除已成功删除的
                let failedFiles = Set(errorDict.values.map { ObjectIdentifier($0) })
                self.mediaFiles.removeAll {
                    !failedFiles.contains(ObjectIdentifier($0.file))
                }
            }
        }
    }

    // MARK: - Helpers

    var selectedItems: [CameraItem] { mediaFiles.filter(\.isSelected) }

    func selectAll()   { mediaFiles.forEach { $0.isSelected = true  } }
    func deselectAll() { mediaFiles.forEach { $0.isSelected = false } }

    private func removeDevice(_ device: ICDevice) {
        devices.removeAll { $0 === device }
        if selectedDevice === device {
            selectedDevice = nil
            mediaFiles     = []
        }
    }
}

// MARK: - ICDeviceBrowserDelegate

extension CameraBrowser: ICDeviceBrowserDelegate {

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser,
                                   didAdd device: ICDevice,
                                   moreComing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        Task { @MainActor in
            devices.append(cam)
            if selectedDevice == nil { selectDevice(cam) }
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser,
                                   didRemove device: ICDevice,
                                   moreGoing: Bool) {
        Task { @MainActor in removeDevice(device) }
    }
}

// MARK: - ICCameraDeviceDelegate
// 修复3: 实现 ICDeviceDelegate 必要方法 didRemove(_:)，消除协议不符合报错

extension CameraBrowser: ICCameraDeviceDelegate {

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didOpenSessionWithError error: (any Error)?) {
        Task { @MainActor in
            if let e = error {
                errorMessage = e.localizedDescription
                isLoading    = false
            }
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didAdd items: [ICCameraItem]) {
        let files = items.compactMap { $0 as? ICCameraFile }
        Task { @MainActor in
            let newItems = files.map { CameraItem($0) }
            mediaFiles.append(contentsOf: newItems)
            isLoading = false
            newItems.forEach { $0.file.requestThumbnail() }
        }
    }

    // 修复4: didRemoveItems → didRemove
    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didRemove items: [ICCameraItem]) {
        let files = Set(items.compactMap { $0 as? ICCameraFile }.map { ObjectIdentifier($0) })
        Task { @MainActor in
            mediaFiles.removeAll { files.contains(ObjectIdentifier($0.file)) }
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceiveThumbnailFor item: ICCameraItem) {
        guard let file = item as? ICCameraFile else { return }
        Task { @MainActor in
            if let ci = mediaFiles.first(where: { $0.file === file }) {
                ci.thumbnail = file.thumbnail
            }
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceiveMetadataFor item: ICCameraItem) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceiveDownloadProgressFor file: ICCameraFile,
                                  downloadedBytes: off_t,
                                  maxBytes: off_t) {}

    // 修复5: didRemoveDevice → didRemove(_:)  (ICDeviceDelegate required)
    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in removeDevice(device) }
    }
}

// MARK: - ICCameraDeviceDownloadDelegate

extension CameraBrowser: ICCameraDeviceDownloadDelegate {}

// MARK: - DownloadHelper (ObjC selector bridge)

final class DownloadHelper: NSObject, ICCameraDeviceDownloadDelegate {
    let file: ICCameraFile
    let dir : URL
    let cont: CheckedContinuation<URL, Error>

    init(file: ICCameraFile, dir: URL, cont: CheckedContinuation<URL, Error>) {
        self.file = file; self.dir = dir; self.cont = cont
    }

    @objc func done(_ f: ICCameraFile, error: Error?, contextInfo: UnsafeRawPointer?) {
        if let e = error { cont.resume(throwing: e) }
        else { cont.resume(returning: dir.appendingPathComponent(f.name ?? "")) }
    }
}

// MARK: - Errors

enum CamError: LocalizedError {
    case noDevice
    var errorDescription: String? {
        switch self { case .noDevice: return "没有已连接的相机设备" }
    }
}
