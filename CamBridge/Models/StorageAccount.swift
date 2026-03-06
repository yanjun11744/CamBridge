// StorageAccount.swift
// 网络存储账号数据模型

import Foundation
import SwiftUI

// MARK: - Provider Type

enum ProviderType: String, Codable, CaseIterable, Identifiable {
    case webdav      = "WebDAV"
    case baiduPan    = "百度网盘"
    case googleDrive = "Google Drive"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .webdav:      return "server.rack"
        case .baiduPan:    return "cloud.fill"
        case .googleDrive: return "externaldrive.connected.to.line.below.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .webdav:      return .blue
        case .baiduPan:    return .indigo
        case .googleDrive: return .green
        }
    }

    var hint: String {
        switch self {
        case .webdav:      return "群晖 NAS · 飞牛 NAS · Nextcloud · 任意 WebDAV"
        case .baiduPan:    return "百度网盘个人版 / 企业版（需申请开放平台 App Key）"
        case .googleDrive: return "Google Drive（需科学上网 · 在 GCP 创建 OAuth 客户端）"
        }
    }
}

// MARK: - StorageAccount

struct StorageAccount: Codable, Identifiable, Hashable {
    var id               = UUID()
    var name             : String
    var type             : ProviderType
    var isEnabled        : Bool   = true

    // WebDAV
    var webdavURL        : String = ""
    var webdavUsername   : String = ""
    var webdavPassKey    : String = ""   // Keychain key

    // 百度网盘
    var baiduAppKey      : String = ""
    var baiduAccessToken : String = ""
    var baiduRefreshToken: String = ""
    var baiduTokenExpiry : Date?

    // Google Drive
    var googleClientID   : String = ""
    var googleClientSecret: String = ""
    var googleAccessToken : String = ""
    var googleRefreshToken: String = ""
    var googleTokenExpiry : Date?

    // 上传配置
    var remotePath           : String = "/"
    var createDateSubfolder  : Bool   = true
    var deleteAfterUpload    : Bool   = false

    static func == (l: Self, r: Self) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Upload Progress / Result

struct UploadProgress {
    var currentFile      : String     = ""
    var filesSent        : Int        = 0
    var filesTotal       : Int        = 0
    var bytesSent        : Int64      = 0
    var bytesTotal       : Int64      = 0
    var speed            : Double     = 0   // bytes/sec
    var eta              : TimeInterval = 0

    var filePercent      : Double { bytesTotal > 0 ? Double(bytesSent)/Double(bytesTotal) : 0 }
    var overallPercent   : Double { filesTotal > 0 ? Double(filesSent)/Double(filesTotal) : 0 }
    var speedText        : String { ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s" }
    var etaText          : String {
        guard eta > 0 else { return "--" }
        let m = Int(eta)/60, s = Int(eta)%60
        return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
    }
}

struct UploadResult: Identifiable {
    let id              = UUID()
    var account         : StorageAccount
    var successCount    : Int    = 0
    var failedCount     : Int    = 0
    var deletedCount    : Int    = 0
    var totalBytes      : Int64  = 0
    var failedItems     : [(name: String, reason: String)] = []
    var startTime       : Date   = Date()
    var endTime         : Date?

    var duration: TimeInterval { (endTime ?? Date()).timeIntervalSince(startTime) }
    var durationText: String {
        let d = Int(duration)
        return d < 60 ? "\(d)秒" : "\(d/60)分\(d%60)秒"
    }
}
