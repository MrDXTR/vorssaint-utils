// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

struct PortManagerEntry: Identifiable, Equatable {
    let port: Int
    let protocolName: String
    let address: String
    let pid: Int32
    let processName: String
    var id: String { "\(protocolName)-\(port)-\(pid)-\(address)" }
}

final class PortManagerService: ObservableObject {
    static let shared = PortManagerService()
    @Published private(set) var entries: [PortManagerEntry] = []
    @Published var query = ""
    @Published private(set) var isRefreshing = false

    var filteredEntries: [PortManagerEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { "\($0.port) \($0.processName) \($0.pid) \($0.address)".lowercased().contains(q) }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.snapshot()
            DispatchQueue.main.async {
                self.entries = result
                self.isRefreshing = false
            }
        }
    }

    func terminate(_ entry: PortManagerEntry, force: Bool) {
        guard entry.pid > 1, entry.pid != Int32(ProcessInfo.processInfo.processIdentifier) else { return }
        _ = Darwin.kill(entry.pid, force ? SIGKILL : SIGTERM)
        refresh()
    }

    private static func snapshot() -> [PortManagerEntry] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcnPT"]
        process.standardOutput = output
        try? process.run()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var name = "", pid: Int32 = 0, address = "", port = 0, proto = "TCP"
        var rows: [PortManagerEntry] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n").map(String.init) {
            guard let type = line.first else { continue }
            let value = String(line.dropFirst())
            switch type {
            case "p":
                pid = Int32(value) ?? 0; port = 0; address = ""
            case "c": name = value
            case "P": proto = value
            case "n":
                address = value
                if let last = value.split(separator: ":").last, let parsed = Int(last) { port = parsed }
                if pid > 0 && port > 0 {
                    let key = "\(proto)|\(port)|\(address)|\(pid)"
                    if seen.insert(key).inserted {
                        rows.append(.init(port: port, protocolName: proto, address: address, pid: pid, processName: name))
                    }
                }
            case "T": continue
            default: continue
            }
        }
        return rows.sorted { $0.port == $1.port ? $0.processName < $1.processName : $0.port < $1.port }
    }
}
