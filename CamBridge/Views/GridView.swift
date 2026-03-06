// GridView.swift
// 中间照片网格 + 搜索/筛选

import SwiftUI

struct GridView: View {
    @Environment(CameraBrowser.self) private var browser
    @Binding var selectedItemID: UUID?

    @State private var searchText  : String          = ""
    @State private var filterType  : MediaType?      = nil  // nil = 全部

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)]
    }

    private var filtered: [CameraItem] {
        browser.mediaFiles.filter { item in
            (filterType == nil || item.mediaType == filterType) &&
            (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(searchText: $searchText, filterType: $filterType, count: filtered.count)
            Divider()

            if browser.selectedDevice == nil {
                CenterHint(icon: "cable.connector", text: "请在左侧选择相机设备")
            } else if browser.isLoading {
                CenterHint(icon: nil, text: "正在读取相机文件…", loading: true)
            } else if filtered.isEmpty {
                CenterHint(icon: "photo.slash",
                           text: searchText.isEmpty && filterType == nil ? "相机中没有媒体文件" : "没有匹配的文件")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(filtered) { item in
                            ThumbnailCell(item: item,
                                          isDetailSelected: item.id == selectedItemID) {
                                selectedItemID = item.id
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .navigationTitle(browser.selectedDevice?.name ?? "CamBridge")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        let sel = browser.selectedItems.count
        let tot = filtered.count
        return sel > 0 ? "已选 \(sel) / \(tot) 项" : "\(tot) 项"
    }
}

// MARK: - Filter Bar

struct FilterBar: View {
    @Binding var searchText : String
    @Binding var filterType : MediaType?
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            // 搜索
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索文件名…", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 7))

            // 类型分段
            Picker("类型", selection: $filterType) {
                Text("全部").tag(MediaType?.none)
                Text("照片").tag(MediaType?.some(.photo))
                Text("RAW").tag(MediaType?.some(.raw))
                Text("视频").tag(MediaType?.some(.video))
            }
            .pickerStyle(.segmented).frame(maxWidth: 260)

            Spacer()
            Text("\(count) 项").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    @Bindable var item: CameraItem
    let isDetailSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 图像
            Group {
                if let img = item.thumbnail {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.fill.secondary)
                        .overlay {
                            Image(systemName: item.mediaType.sfSymbol)
                                .font(.system(size: 28)).foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: 140, height: 105).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 勾选框
            CheckCircle(checked: item.isSelected)
                .padding(5)
                .onTapGesture { item.isSelected.toggle() }

            // 媒体角标
            if item.mediaType != .photo {
                Text(item.ext).font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(5)
            }

            // 上传进度
            if item.isUploading {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.45))
                    .overlay {
                        VStack(spacing: 5) {
                            ProgressView(value: item.uploadProgress).tint(.white).padding(.horizontal, 14)
                            Text("\(Int(item.uploadProgress * 100))%").font(.caption2).foregroundStyle(.white)
                        }
                    }
            }

            // 已完成角标
            if item.isUploaded {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                    .foregroundStyle(.green).background(Circle().fill(.white))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(width: 140, height: 105)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isDetailSelected ? Color.accentColor : .clear, lineWidth: 2))
        .onTapGesture { onTap() }
        .onTapGesture(count: 2) { item.isSelected.toggle() }
        .contextMenu {
            Button(item.isSelected ? "取消选择" : "选择") { item.isSelected.toggle() }
        }
    }
}

// MARK: - Check Circle

struct CheckCircle: View {
    let checked: Bool
    var body: some View {
        ZStack {
            Circle().fill(checked ? Color.accentColor : .black.opacity(0.2))
            Circle().stroke(checked ? Color.accentColor : Color.white.opacity(0.85), lineWidth: 1.5)
            if checked {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Center Hint

struct CenterHint: View {
    let icon   : String?
    let text   : String
    var loading: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            if loading {
                ProgressView().controlSize(.large)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 52)).foregroundStyle(.tertiary)
            }
            Text(text).font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
