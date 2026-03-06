// DetailView.swift
// 右侧文件详情面板

import SwiftUI

struct DetailView: View {
    @Bindable var item: CameraItem

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                previewArea
                Divider()
                metaArea
            }
        }
        .navigationTitle(item.name)
    }

    // MARK: - Preview

    private var previewArea: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.06)).frame(maxWidth: .infinity).frame(height: 260)

            if let img = item.thumbnail {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 260)
            } else {
                Image(systemName: item.mediaType.sfSymbol)
                    .font(.system(size: 52)).foregroundStyle(.tertiary)
            }

            if item.isUploading {
                Rectangle().fill(.black.opacity(0.45)).frame(maxWidth: .infinity, maxHeight: 260)
                    .overlay {
                        VStack(spacing: 10) {
                            ProgressView(value: item.uploadProgress).tint(.white).padding(.horizontal, 32)
                            Text("上传中 \(Int(item.uploadProgress * 100))%")
                                .foregroundStyle(.white).font(.headline)
                        }
                    }
            }
        }
    }

    // MARK: - Metadata

    private var metaArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("文件信息").font(.headline).padding(16)

            Group {
                MetaRow(icon: "doc",          label: "文件名",  value: item.name)
                MetaRow(icon: "internaldrive", label: "大小",   value: item.formattedSize)
                MetaRow(icon: "calendar",      label: "日期",   value: item.formattedDate)
                MetaRow(icon: "tag",           label: "格式",   value: item.ext)
                MetaRow(icon: "photo",         label: "类型",   value: item.mediaType.label)
            }

            if item.isUploaded {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("已上传到云端").foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.green.opacity(0.08))
            }
        }
    }
}

struct MetaRow: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
                Text(label).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                Text(value).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            Divider().padding(.leading, 46)
        }
    }
}

extension MediaType {
    var label: String {
        switch self {
        case .photo:   return "照片"
        case .video:   return "视频"
        case .raw:     return "RAW 原始文件"
        case .unknown: return "未知"
        }
    }
}
