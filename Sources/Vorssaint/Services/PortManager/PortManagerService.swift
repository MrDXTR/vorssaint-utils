// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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
        guard let startedAt = entry.startedAt else { return }
        KillProcessService.shared.kill(pid: entry.pid,
                                       name: entry.processName,
                                       startedAt: startedAt,
                                       force: force) { [weak self] in
            self?.refresh()
        }
    }

    private static func snapshot() -> [PortManagerEntry] {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN", "-F", "pcnPT"])
        guard result.status == 0 else { return [] }
        return PortManagerSupport.parseLsof(result.output).map { entry in
            PortManagerEntry(port: entry.port,
                             protocolName: entry.protocolName,
                             address: entry.address,
                             pid: entry.pid,
                             processName: entry.processName,
                             startedAt: KillProcessService.startTime(for: entry.pid))
        }
    }

}
