// BaiduPanService.swift
// 百度网盘开放平台 API — 分片上传（4 MB/块）
// 文档: https://pan.baidu.com/union/document/basic

import Foundation
import CommonCrypto

enum BaiduError: LocalizedError {
    case noToken, api(Int, String), upload(String)
    var errorDescription: String? {
        switch self {
        case .noToken:        return "请先完成百度网盘授权"
        case .api(let c, let m): return "百度API错误 [\(c)] \(m)"
        case .upload(let m):  return "上传失败：\(m)"
        }
    }
}

final class BaiduPanService {

    // ---- 在百度开放平台申请 ----
    static var appKey    = "YOUR_BAIDU_APP_KEY"
    static var secretKey = "YOUR_BAIDU_SECRET_KEY"
    static let redirectURI = "oob"

    private let account : StorageAccount
    private let session : URLSession

    init(account: StorageAccount) {
        self.account = account
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 7200
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - OAuth

    static func authURL() -> URL {
        URL(string: "https://openapi.baidu.com/oauth/2.0/authorize?response_type=code&client_id=\(appKey)&redirect_uri=\(redirectURI)&scope=netdisk&display=popup")!
    }

    static func exchangeToken(code: String) async throws -> (access: String, refresh: String, expIn: Int) {
        let url = URL(string: "https://openapi.baidu.com/oauth/2.0/token?grant_type=authorization_code&code=\(code)&client_id=\(appKey)&client_secret=\(secretKey)&redirect_uri=\(redirectURI)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = j["access_token"] as? String else { throw BaiduError.upload("token exchange failed") }
        return (at, j["refresh_token"] as? String ?? "", j["expires_in"] as? Int ?? 2592000)
    }

    // MARK: - Upload (分片 4 MB)

    private let chunkSize = 4 * 1024 * 1024

    func upload(localURL: URL, remotePath: String,
                onProgress: @Sendable @escaping (Int64, Int64) -> Void) async throws {
        let token = account.baiduAccessToken
        guard !token.isEmpty else { throw BaiduError.noToken }

        let data  = try Data(contentsOf: localURL)
        let size  = Int64(data.count)
        let fname = localURL.lastPathComponent
        let fpath = remotePath.hasSuffix("/") ? "\(remotePath)\(fname)" : "\(remotePath)/\(fname)"

        // 分块 MD5
        var blockMD5s: [String] = []
        var offset = 0
        while offset < data.count {
            let end   = min(offset + chunkSize, data.count)
            blockMD5s.append(md5(data[offset..<end]))
            offset = end
        }

        // 1. Precreate
        let uploadID = try await precreate(path: fpath, size: size, blocks: blockMD5s, token: token)

        // 2. Upload chunks
        offset = 0
        for (i, _) in blockMD5s.enumerated() {
            let end   = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            try await uploadChunk(Data(chunk), path: fpath, uploadID: uploadID, seq: i, token: token)
            onProgress(Int64(end), size)
            offset = end
        }

        // 3. Create (commit)
        try await commit(path: fpath, size: size, uploadID: uploadID, blocks: blockMD5s,
                         md5: md5(data), token: token)
        onProgress(size, size)
    }

    // MARK: - Steps

    private func precreate(path: String, size: Int64, blocks: [String], token: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://pan.baidu.com/rest/2.0/xpan/file?method=precreate&access_token=\(token)")!)
        req.httpMethod = "POST"
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bl  = "[\(blocks.map { "\"\($0)\"" }.joined(separator: ","))]"
        let ep  = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        req.httpBody = "path=\(ep)&size=\(size)&isdir=0&autoinit=1&block_list=\(bl)&rtype=3".data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        let j = try json(data)
        guard let uid = j["uploadid"] as? String else { throw BaiduError.upload("no uploadid") }
        return uid
    }

    private func uploadChunk(_ chunk: Data, path: String, uploadID: String, seq: Int, token: String) async throws {
        let ep = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let url = URL(string: "https://d.pcs.baidu.com/rest/2.0/pcs/superfile2?method=upload&access_token=\(token)&path=\(ep)&type=tmpfile&uploadid=\(uploadID)&partseq=\(seq)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "CB\(UUID().uuidString.prefix(8))"
        req.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"part\"\r\n\r\n".data(using: .utf8)!
        body += chunk
        body += "\r\n--\(boundary)--\r\n".data(using: .utf8)!
        req.httpBody = body
        let (data, _) = try await session.data(for: req)
        let j = try json(data)
        if let e = j["errno"] as? Int, e != 0 { throw BaiduError.api(e, "chunk upload") }
    }

    private func commit(path: String, size: Int64, uploadID: String,
                        blocks: [String], md5: String, token: String) async throws {
        var req = URLRequest(url: URL(string: "https://pan.baidu.com/rest/2.0/xpan/file?method=create&access_token=\(token)")!)
        req.httpMethod = "POST"
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let ep = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let bl = "[\(blocks.map { "\"\($0)\"" }.joined(separator: ","))]"
        req.httpBody = "path=\(ep)&size=\(size)&isdir=0&uploadid=\(uploadID)&block_list=\(bl)&content-md5=\(md5)&rtype=3".data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        let j = try json(data)
        if let e = j["errno"] as? Int, e != 0 { throw BaiduError.api(e, "commit") }
    }

    // MARK: - Helpers

    private func json(_ data: Data) throws -> [String: Any] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BaiduError.upload("invalid json")
        }
        return j
    }

    private func md5(_ data: some DataProtocol) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        let bytes  = Array(data)
        CC_MD5(bytes, CC_LONG(bytes.count), &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
