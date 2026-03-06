// AccountManager.swift
// 网络存储账号持久化管理

import Foundation
import SwiftUI

@MainActor
@Observable
final class AccountManager {

    var accounts: [StorageAccount] = []

    private let key = "cam_bridge_accounts_v2"

    init() { load() }

    // MARK: - CRUD

    func add(_ account: StorageAccount) {
        accounts.append(account)
        save()
    }

    func update(_ account: StorageAccount) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i] = account
        save()
    }

    func delete(_ account: StorageAccount) {
        KeychainHelper.delete(forKey: account.webdavPassKey)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func move(from src: IndexSet, to dst: Int) {
        accounts.move(fromOffsets: src, toOffset: dst)
        save()
    }

    var enabled: [StorageAccount] { accounts.filter(\.isEnabled) }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StorageAccount].self, from: data)
        else { return }
        accounts = decoded
    }

    // MARK: - WebDAV Test

    func testWebDAV(_ account: StorageAccount) async -> String {
        do {
            let svc = WebDAVService(account: account)
            try await svc.testConnection()
            return "✅ 连接成功，服务器响应正常。"
        } catch {
            return "❌ 连接失败：\(error.localizedDescription)"
        }
    }
}
