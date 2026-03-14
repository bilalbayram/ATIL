import SwiftUI

@Observable
@MainActor
final class ProcessListViewModel {
    let monitor: ProcessMonitor
    private let actionService = ProcessActionService()
    private let safetyGate = SafetyGate.shared
    private let statsRepo = StatsRepository(db: DatabaseManager.shared)
    private let killHistoryRepo = KillHistoryRepository(db: DatabaseManager.shared)

    // State
    var searchText = ""
    var selectedProcessID: ProcessIdentity?
    var expandedCategories: Set<ProcessCategory> = [.redundant, .suspicious, .quarantined]
    var showGrouped = true
    var lastError: String?

    // Session stats
    var sessionKillCount = 0
    var sessionMemoryFreed: UInt64 = 0

    // Lifetime stats (from SQLite)
    var lifetimeKills: Int64 = 0
    var lifetimeMemoryFreed: Int64 = 0

    init(monitor: ProcessMonitor? = nil) {
        self.monitor = monitor ?? ProcessMonitor()
        loadLifetimeStats()
    }

    // MARK: - Computed

    var filteredProcesses: [ATILProcess] {
        let all = monitor.snapshot
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter { p in
            p.name.lowercased().contains(query)
            || "\(p.pid)".contains(query)
            || (p.executablePath?.lowercased().contains(query) ?? false)
            || (p.bundleIdentifier?.lowercased().contains(query) ?? false)
        }
    }

    var categorizedProcesses: [(category: ProcessCategory, processes: [ATILProcess])] {
        let grouped = Dictionary(grouping: filteredProcesses, by: \.category)
        return ProcessCategory.allCases.compactMap { cat in
            guard let procs = grouped[cat], !procs.isEmpty else { return nil }
            return (category: cat, processes: procs.sorted { $0.residentMemory > $1.residentMemory })
        }
    }

    var selectedProcess: ATILProcess? {
        guard let id = selectedProcessID else { return nil }
        return monitor.snapshot.first { $0.identity == id }
    }

    var totalRedundantMemory: UInt64 {
        monitor.snapshot
            .filter { $0.category == .redundant }
            .reduce(0) { $0 + $1.residentMemory }
    }

    /// Processes grouped by app bundle for display.
    var groupedProcesses: [ProcessCategory: [ProcessGroup]] {
        let cats = Dictionary(grouping: filteredProcesses, by: \.category)
        var result: [ProcessCategory: [ProcessGroup]] = [:]
        for (cat, procs) in cats {
            result[cat] = ProcessGroup.group(procs)
        }
        return result
    }

    /// Whether the selected process is suspended (quarantined).
    var isSelectedSuspended: Bool {
        selectedProcess?.processState == .suspended
    }

    /// Whether the selected process can be relaunched after kill.
    var canRelaunchSelected: Bool {
        guard let process = selectedProcess else { return false }
        return process.bundlePath != nil || process.launchdJob != nil
    }

    // MARK: - Actions

    func refresh() async {
        await monitor.scan()
    }

    func killSelected() async {
        guard let process = selectedProcess else { return }
        guard !safetyGate.isProtected(process) else {
            lastError = "Cannot kill protected process: \(process.name)"
            return
        }

        do {
            let freedMemory = try await actionService.kill(process: process)
            sessionKillCount += 1
            sessionMemoryFreed += freedMemory
            selectedProcessID = nil
            loadLifetimeStats()
            await monitor.scan()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func suspendSelected() {
        guard let process = selectedProcess else { return }
        guard !safetyGate.isProtected(process) else {
            lastError = "Cannot suspend protected process: \(process.name)"
            return
        }

        do {
            try actionService.suspend(process: process)
            Task { await monitor.scan() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resumeSelected() {
        guard let process = selectedProcess else { return }
        if actionService.resume(pid: process.pid) {
            Task { await monitor.scan() }
        } else {
            lastError = "Failed to resume process"
        }
    }

    func toggleSuspendResume() {
        if isSelectedSuspended {
            resumeSelected()
        } else {
            suspendSelected()
        }
    }

    func relaunchSelected() {
        guard let process = selectedProcess else { return }
        do {
            try actionService.relaunch(process: process)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func ignoreSelected() {
        guard let process = selectedProcess else { return }
        safetyGate.ignore(process)
        Task { await monitor.scan() }
    }

    func startMonitoring() {
        monitor.startPolling()
        Task { await monitor.scan() }
    }

    func stopMonitoring() {
        monitor.stopPolling()
    }

    // MARK: - Private

    private func loadLifetimeStats() {
        lifetimeKills = (try? statsRepo.totalKills()) ?? 0
        lifetimeMemoryFreed = (try? statsRepo.totalMemoryFreed()) ?? 0
    }
}
