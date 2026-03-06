// CameraBrowser.swift
// MTP/PTP 设备浏览与文件管理

import Foundation
import ImageCaptureCore
import AppKit

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
    // deinit 是 nonisolated 的，nonisolated(unsafe) 允许其访问此属性
    // deinit 时对象已无其他引用，天然无并发竞争，unsafe 是安全的
    nonisolated(unsafe) private var browser: ICDeviceBrowser?

    // MARK: - Init / Deinit

    override init() {
        super.init()
        startBrowsing()
    }

    deinit {
        browser?.stop()
        browser?.delegate = nil
    }

    // MARK: - Browsing

    func startBrowsing() {
        browser?.stop()
        let b = ICDeviceBrowser()
        b.delegate = self
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

    func downloadToTemp(_ item: CameraItem) async throws -> URL {
        guard let device = selectedDevice else { throw CamError.noDevice }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try await download(item.file, device: device, to: dir)
    }

    func downloadFile(_ item: CameraItem, to directory: URL) async throws -> URL {
        guard let device = selectedDevice else { throw CamError.noDevice }
        return try await download(item.file, device: device, to: directory)
    }

    private func download(_ file: ICCameraFile,
                          device: ICCameraDevice,
                          to dir: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: dir,
                .saveAsFilename       : file.name ?? UUID().uuidString,
                .overwrite            : true
            ]
            let helper = DownloadHelper(file: file, dir: dir, cont: cont)
            device.requestDownloadFile(
                file,
                options             : options,
                downloadDelegate    : helper,
                didDownloadSelector : #selector(DownloadHelper.done(_:error:contextInfo:)),
                contextInfo         : nil
            )
        }
    }

    func deleteItems(_ items: [CameraItem]) {
        selectedDevice?.requestDeleteFiles(items.map(\.file))
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
// 方法签名完全来自 Xcode "Add protocol stubs" 自动生成，确保与当前 SDK 一致

extension CameraBrowser: ICCameraDeviceDelegate {
    
    // 所有文件枚举完成（相机内容目录加载完毕）
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in
            isLoading = false
        }
    }
    

    // 会话打开回调（新签名：device(_:didOpenSessionWithError:)）
    nonisolated func device(_ device: ICDevice,
                            didOpenSessionWithError error: (any Error)?) {
        Task { @MainActor in
            if let e = error {
                errorMessage = e.localizedDescription
                isLoading    = false
            }
        }
    }

    // 会话关闭回调
    nonisolated func device(_ device: ICDevice,
                            didCloseSessionWithError error: (any Error)?) {
        Task { @MainActor in
            if let e = error {
                errorMessage = e.localizedDescription
            }
        }
    }

    // 新增文件（首次枚举 + 热插拔新增）
    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didAdd items: [ICCameraItem]) {
        let files = items.compactMap { $0 as? ICCameraFile }
        Task { @MainActor in
            let newItems = files.map { CameraItem($0) }
            mediaFiles.append(contentsOf: newItems)
            // 请求缩略图（回调到 didReceiveThumbnail）
            files.forEach { $0.requestThumbnail() }
        }
    }

    // 移除文件
    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didRemove items: [ICCameraItem]) {
        let ids = Set(items.compactMap { $0 as? ICCameraFile }.map { ObjectIdentifier($0) })
        Task { @MainActor in
            mediaFiles.removeAll { ids.contains(ObjectIdentifier($0.file)) }
        }
    }

    // 缩略图就绪（新签名：thumbnail 直接作为参数传入，不需要再读 file.thumbnail）
    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceiveThumbnail thumbnail: CGImage?,
                                  for item: ICCameraItem,
                                  error: (any Error)?) {
        guard let file = item as? ICCameraFile,
              let cgImage = thumbnail else { return }
        Task { @MainActor in
            guard let ci = mediaFiles.first(where: { $0.file === file }) else { return }
            ci.thumbnail = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }
    }

    // 元数据就绪（新签名：metadata 直接作为参数传入）
    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceiveMetadata metadata: [AnyHashable: Any]?,
                                  for item: ICCameraItem,
                                  error: (any Error)?) {
        // 暂不处理，预留扩展（如读取 EXIF）
    }

    // 文件重命名
    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didRenameItems items: [ICCameraItem]) {
        // mediaFiles 里的 CameraItem 持有 ICCameraFile 引用
        // ICCameraFile.name 已自动更新，触发视图刷新即可
        Task { @MainActor in
            mediaFiles = mediaFiles
        }
    }

    // 设备能力变化（如切换拍摄模式）
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    // PTP 事件（原始协议事件，暂不处理）
    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceivePTPEvent eventData: Data) {}

    // 访问限制变化
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in
            errorMessage = "相机已启用访问限制，请检查相机设置。"
        }
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in
            errorMessage = nil
        }
    }

    // ICDeviceDelegate required — 设备断开
    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in removeDevice(device) }
    }
}

// MARK: - ICCameraDeviceDownloadDelegate

extension CameraBrowser: ICCameraDeviceDownloadDelegate {}

// MARK: - DownloadHelper（ObjC selector bridge）

final class DownloadHelper: NSObject, ICCameraDeviceDownloadDelegate {
    let file: ICCameraFile
    let dir : URL
    let cont: CheckedContinuation<URL, Error>

    init(file: ICCameraFile, dir: URL, cont: CheckedContinuation<URL, Error>) {
        self.file = file; self.dir = dir; self.cont = cont
    }

    @objc func done(_ f: ICCameraFile, error: Error?, contextInfo: UnsafeRawPointer?) {
        if let e = error { cont.resume(throwing: e) }
        else { cont.resume(returning: dir.appendingPathComponent(f.name ?? "file")) }
    }
}

// MARK: - Errors

enum CamError: LocalizedError {
    case noDevice
    var errorDescription: String? {
        switch self { case .noDevice: return "没有已连接的相机设备" }
    }
}
