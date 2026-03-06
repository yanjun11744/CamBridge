// GoogleDriveService.swift
// Google Drive REST API v3 — Resumable Upload（8 MB/块）

import Foundation

enum GDriveError: LocalizedError {
    case noToken, api(Int), upload(String), folderNotFound
    var errorDescription: String? {
        switch self {
        case .noToken:        return "请先完成 Google Drive 授权"
        case .api(let c):     return "Google API 错误 HTTP \(c)"
        case .upload(let m):  return "上传失败：\(m)"
        case .folderNotFound: return "目标文件夹不存在"
        }
    }
}

final class GoogleDriveService {

    // ---- 在 Google Cloud Console 创建 OAuth 2.0 桌面客户端 ----
    static var clientID     = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
    static var clientSecret = "YOUR_GOOGLE_CLIENT_SECRET"
    static let redirectURI  = "urn:ietf:wg:oauth:2.0:oob"
    static let scope        = "https://www.googleapis.com/auth/drive.file"

    private var account : StorageAccount
    private let session : URLSession

    init(account: StorageAccount) {
        self.account = account
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 7200
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - OAuth

    static func authURL() -> URL {
        URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scope)&access_type=offline&prompt=consent")!
    }

    static func exchangeToken(code: String) async throws -> (access: String, refresh: String, expIn: Int) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "code=\(code)&client_id=\(clientID)&client_secret=\(clientSecret)&redirect_uri=\(redirectURI)&grant_type=authorization_code".data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = j["access_token"] as? String else { throw GDriveError.upload("token exchange failed") }
        return (at, j["refresh_token"] as? String ?? "", j["expires_in"] as? Int ?? 3600)
    }

    // MARK: - Refresh Token

    private func refreshIfNeeded() async throws {
        guard let exp = account.googleTokenExpiry, exp < Date() else { return }
        let rt = account.googleRefreshToken
        guard !rt.isEmpty else { throw GDriveError.noToken }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "client_id=\(Self.clientID)&client_secret=\(Self.clientSecret)&refresh_token=\(rt)&grant_type=refresh_token".data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = j["access_token"] as? String else { throw GDriveError.noToken }
        account.googleAccessToken = at
        account.googleTokenExpiry = Date().addingTimeInterval(TimeInterval(j["expires_in"] as? Int ?? 3600))
    }

    // MARK: - Find / Create Folder

    func findOrCreateFolder(name: String, parentID: String = "root") async throws -> String {
        try await refreshIfNeeded()
        let token = account.googleAccessToken
        guard !token.isEmpty else { throw GDriveError.noToken }

        let q = "name='\(name)' and mimeType='application/vnd.google-apps.folder' and '\(parentID)' in parents and trashed=false"
        var searchReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!)
        searchReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (sd, _) = try await session.data(for: searchReq)
        if let j = try? JSONSerialization.jsonObject(with: sd) as? [String: Any],
           let files = j["files"] as? [[String: Any]],
           let fid = files.first?["id"] as? String { return fid }

        // Create
        var cr = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        cr.httpMethod = "POST"
        cr.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        cr.addValue("application/json", forHTTPHeaderField: "Content-Type")
        cr.httpBody = try? JSONSerialization.data(withJSONObject: [
            "name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [parentID]
        ])
        let (cd, _) = try await session.data(for: cr)
        guard let cj = try? JSONSerialization.jsonObject(with: cd) as? [String: Any],
              let id = cj["id"] as? String else { throw GDriveError.folderNotFound }
        return id
    }

    // MARK: - Resumable Upload

    private let chunkSize = 8 * 1024 * 1024

    func upload(localURL: URL, folderID: String,
                onProgress: @Sendable @escaping (Int64, Int64) -> Void) async throws {
        try await refreshIfNeeded()
        let token    = account.googleAccessToken
        guard !token.isEmpty else { throw GDriveError.noToken }

        let fname    = localURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        let mime     = mimeType(for: fname)

        // Init resumable session
        var initReq  = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!)
        initReq.httpMethod = "POST"
        initReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initReq.addValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initReq.addValue(mime, forHTTPHeaderField: "X-Upload-Content-Type")
        initReq.addValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        initReq.httpBody = try? JSONSerialization.data(withJSONObject: ["name": fname, "parents": [folderID]])

        let (_, initResp) = try await session.data(for: initReq)
        guard let http = initResp as? HTTPURLResponse,
              let uploadURLStr = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: uploadURLStr) else { throw GDriveError.upload("no upload URL") }

        // Upload in chunks
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }
        var offset: Int64 = 0

        while offset < fileSize {
            let chunkLen = min(Int64(chunkSize), fileSize - offset)
            try handle.seek(toOffset: UInt64(offset))
            let chunk    = try handle.read(upToCount: Int(chunkLen))

            var cr = URLRequest(url: uploadURL)
            cr.httpMethod = "PUT"
            cr.addValue("bytes \(offset)-\(offset+chunkLen-1)/\(fileSize)", forHTTPHeaderField: "Content-Range")
            cr.addValue(mime, forHTTPHeaderField: "Content-Type")
            cr.httpBody = chunk

            let (_, resp) = try await session.data(for: cr)
            let sc = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch sc {
            case 200, 201: offset = fileSize; onProgress(fileSize, fileSize)
            case 308:      offset += chunkLen; onProgress(offset, fileSize)
            default:       throw GDriveError.api(sc)
            }
        }
    }

    private func mimeType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg","jpeg": return "image/jpeg"
        case "png":        return "image/png"
        case "heic","heif":return "image/heic"
        case "mp4":        return "video/mp4"
        case "mov":        return "video/quicktime"
        default:           return "application/octet-stream"
        }
    }
}
