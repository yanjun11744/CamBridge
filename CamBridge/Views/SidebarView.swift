// SidebarView.swift
// 左侧设备列表

import SwiftUI
import ImageCaptureCore

struct SidebarView: View {
    @Environment(CameraBrowser.self) private var browser

    var body: some View {
        @Bindable var browser = browser

        List(selection: Binding(
            get: { browser.selectedDevice.map { ObjectIdentifier($0) } },
            set: { id in
                if let id, let dev = browser.devices.first(where: { ObjectIdentifier($0) == id }) {
                    browser.selectDevice(dev)
                }
            }
        )) {
            Section {
                if browser.devices.isEmpty {
                    NoDeviceRow()
                } else {
                    ForEach(browser.devices, id: \.self) { dev in
                        DeviceRow(device: dev)
                            .tag(ObjectIdentifier(dev))
                    }
                }
            } header: {
                HStack {
                    Text("已连接设备")
                    Spacer()
                    Button { browser.startBrowsing() } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("刷新")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CamBridge")
    }
}

struct DeviceRow: View {
    let device: ICCameraDevice

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                // 替换后
                Image(systemName: device.transportType == "WiFi" ? "camera.on.rectangle.fill" : "camera.fill")
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name ?? "未知相机")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    // 暂时固定显示绿色，后续补充正确属性
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(device.transportType == "WiFi" ? "WiFi" : "USB")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct NoDeviceRow: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 36)).foregroundStyle(.tertiary).padding(.top, 16)
            Text("未检测到相机").font(.headline).foregroundStyle(.secondary)
            Text("请连接相机后重试").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
