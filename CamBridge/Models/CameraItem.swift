// CameraItem.swift
// 相机文件的包装模型

import Foundation
import ImageCaptureCore
import AppKit

// MARK: - Media Type

enum MediaType: String {
    case photo, video, raw, unknown

    var sfSymbol: String {
        switch self {
        case .photo:   return "photo"
        case .video:   return "video"
        case .raw:     return "camera.aperture"
        case .unknown: return "doc"
        }
    }

    static func from(extension ext: String) -> MediaType {
        switch ext.lowercased() {
        case "jpg","jpeg","heic","heif","png","tiff","tif": return .photo
        case "mp4","mov","avi","m4v":                       return .video
        case "cr2","cr3","nef","arw","orf","raf","dng","rw2","raw": return .raw
        default:                                            return .unknown
        }
    }
}

// MARK: - CameraItem

/// ICCameraFile 的可观察包装，持有上传/下载状态
@MainActor
@Observable
final class CameraItem: Identifiable {
    let id            = UUID()
    let file          : ICCameraFile

    var thumbnail     : NSImage?
    var isSelected    : Bool   = false
    var isUploading   : Bool   = false
    var uploadProgress: Double = 0   // 0.0 – 1.0
    var isUploaded    : Bool   = false

    init(_ file: ICCameraFile) { self.file = file }

    // MARK: Computed

    var name          : String  { file.name ?? "未知" }
    var fileSize      : Int64   { Int64(file.fileSize) }
    var creationDate  : Date?   { file.creationDate }
    var ext           : String  { (name as NSString).pathExtension.uppercased() }
    var mediaType     : MediaType { .from(extension: ext) }

    var formattedSize : String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    var formattedDate : String {
        guard let d = creationDate else { return "未知日期" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: d)
    }
}
