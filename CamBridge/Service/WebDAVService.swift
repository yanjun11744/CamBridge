// WebDAVService.swift
// WebDAV 上传 — 群晖 DSM · 飞牛 NAS · Nextcloud · Any WebDAV

import Foundation
import ImageCaptureCore

enum WebDAVError: LocalizedError {
    case badURL, authFailed, server(Int), upload(String)
    var errorDescription: String? {
        switch self {
        case .badURL:       return "WebDAV 地址格式错误"
        case .authFailed:   return "用户名或密码错误（401）"
        case .server(let c):return "服务器错误 HTTP \(c)"
        case .upload(let m):return "上传失败：\(m)"
        }
    }
}

final class WebDAVService {

    private let account : StorageAccount
    private let session : URLSession
    private let base    : URL

    init(account: StorageAccount) {
        self.account = account
        self.base    = URL(string: account.webdavURL) ?? URL(string: "http://localhost")!
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 7200
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Test Connection (PROPFIND)

    func testConnection() async throws {
        var req = request(base, method: "PROPFIND")
        req.addValue("0", forHTTPHeaderField: "Depth")
        let (_, resp) = try await session.data(for: req)
        try checkHTTP(resp, allowed: [200, 207])
    }

    // MARK: - Upload File

    /// localURL: 本地临时文件；remotePath: 远端目录（不含文件名）
    func upload(
        localURL     : URL,
        remotePath   : String,
        onProgress   : @Sendable @escaping (Int64, Int64) -> Void
    ) async throws {

        // 确保远端目录存在
        let dirURL = base.appendingPathComponent(remotePath)
        var mkcolReq = request(dirURL, method: "MKCOL")
        let (_, mkcolResp) = try await session.data(for: mkcolReq)
        // 201=Created, 405=Already exists — 都可以
        if let h = mkcolResp as? HTTPURLResponse,
           h.statusCode != 201, h.statusCode != 405, h.statusCode != 301 {
            // 忽略其他非致命状态，继续上传
        }

        // PUT 文件
        let fileName  = localURL.lastPathComponent
        let fileURL   = dirURL.appendingPathComponent(fileName)
        let fileSize  = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        var putReq    = request(fileURL, method: "PUT")
        putReq.addValue(mime(for: fileName), forHTTPHeaderField: "Content-Type")
        putReq.addValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

        let delegate = ProgressDelegate(total: fileSize, cb: onProgress)
        let delegateSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (_, putResp) = try await delegateSession.upload(for: putReq, fromFile: localURL)
        try checkHTTP(putResp, allowed: Array(200...299))
    }

    // MARK: - Helpers

    private func request(_ url: URL, method: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        if let cred = basicAuth() { r.addValue(cred, forHTTPHeaderField: "Authorization") }
        r.addValue("CamBridge/1.0", forHTTPHeaderField: "User-Agent")
        return r
    }

    private func basicAuth() -> String? {
        let pass = KeychainHelper.load(forKey: account.webdavPassKey) ?? ""
        guard let data = "\(account.webdavUsername):\(pass)".data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    private func checkHTTP(_ resp: URLResponse, allowed: [Int]) throws {
        guard let h = resp as? HTTPURLResponse else { return }
        if h.statusCode == 401 { throw WebDAVError.authFailed }
        if !allowed.contains(h.statusCode) { throw WebDAVError.server(h.statusCode) }
    }

    private func mime(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg","jpeg": return "image/jpeg"
        case "png":        return "image/png"
        case "heic","heif":return "image/heic"
        case "tiff","tif": return "image/tiff"
        case "mp4":        return "video/mp4"
        case "mov":        return "video/quicktime"
        default:           return "application/octet-stream"
        }
    }
}

// MARK: - Upload Progress Delegate

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let total: Int64
    let cb   : @Sendable (Int64, Int64) -> Void
    init(total: Int64, cb: @Sendable @escaping (Int64, Int64) -> Void) { self.total = total; self.cb = cb }

    func urlSession(_ s: URLSession, task: URLSessionTask,
                    didSendBodyData: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        cb(totalBytesSent, totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : total)
    }
}
