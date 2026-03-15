import SwiftUI

@Observable
@MainActor
final class ProcessListViewModel {
    let monitor: ProcessMonitor
    private let actionService = ProcessActionService()
    private let safetyGate = SafetyGate.shared
    private let statsRepo = StatsRepository(db: DatabaseManager.shared)
    private let killHistoryRepo = KillHistoryRepository(db: DatabaseManager.shared)
    private let preferencesRepo = PreferencesRepository(db: DatabaseManager.shared)

    // State
    var searchText = ""
    var searchFocusNonce = 0
    var selectedProcessID: ProcessIdentity? {
        didSet {
            monitor.focusedProcessID = selectedProcessID
        }
    }
    var selectedProcessIDs: Set<ProcessIdentity> = []
    var expandedCategories: Set<ProcessCategory> = [.redundant, .suspicious, .quarantined]
    var expandedGroupIDs: Set<String> = []
    var showGrouped = true {
        didSet {
            try? preferencesRepo.set(showGrouped ? "true" : "false", forKey: "showGrouped")
        }
    }
    var lastError: String?
    var showingRuleBuilder = false
    var ruleBuilderRule: AutoRule?
    var showingLaunchdConfirmation = false
    var launchdConfirmProcess: ATILProcess?
    let sessionStartedAt = Date()

    // Session stats
    var sessionKillCount = 0
    var sessionMemoryFreed: UInt64 = 0
    var pollingIntervalSeconds = 60

    // Lifetime stats (from SQLite)
    var lifetimeKills: Int64 = 0
    var lifetimeMemoryFreed: Int64 = 0

    init(monitor: ProcessMonitor? = nil) {
        self.monitor = monitor ?? ProcessMonitor()
        loadPreferences()
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

        // Check for launchd respawn — show confirmation if needed
        if let job = process.launchdJob, job.willRespawn {
            launchdConfirmProcess = process
            showingLaunchdConfirmation = true
            return
        }

        await performKill(process: process)
    }

    func performKill(process: ATILProcess) async {
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

    func killAndDisableRespawn(process: ATILProcess) async {
        if let job = process.launchdJob {
            do {
                try await HelperClient.shared.disableLaunchdJob(label: job.label, domain: job.domain)
            } catch {
                let serviceTarget = "\(job.domain)/\(job.label)"
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                task.arguments = ["disable", serviceTarget]
                try? task.run()
                task.waitUntilExit()
            }
        }

        await performKill(process: process)
        showingLaunchdConfirmation = false
        launchdConfirmProcess = nil
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

    func toggleSuspendResumeForSelection() {
        if selectedProcessIDs.count == 1 {
            toggleSuspendResume()
            return
        }

        for process in selectedProcesses {
            if process.processState == .suspended {
                _ = actionService.resume(pid: process.pid)
            } else if !safetyGate.isProtected(process), process.isUserOwned {
                try? actionService.suspend(process: process)
            }
        }

        Task { await monitor.scan() }
    }

    func relaunch(_ record: KillHistoryRecord) {
        do {
            try actionService.relaunch(record: record)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func ignoreSelected() {
        guard let process = selectedProcess else { return }
        safetyGate.ignore(process)
        Task { await monitor.scan() }
    }

    func createRuleFromSelected() {
        guard let process = selectedProcess else { return }
        ruleBuilderRule = monitor.ruleEngine.createRuleFromProcess(process, action: .kill)
        showingRuleBuilder = true
    }

    func saveRule(_ rule: AutoRule) {
        let ruleRepo = RuleRepository(db: DatabaseManager.shared)
        _ = try? ruleRepo.save(rule)
        showingRuleBuilder = false
        ruleBuilderRule = nil
    }

    // MARK: - Bulk Operations

    var selectedProcesses: [ATILProcess] {
        monitor.snapshot.filter { selectedProcessIDs.contains($0.identity) }
    }

    var hasMultipleSelection: Bool {
        selectedProcessIDs.count > 1
    }

    var visibleProcesses: [ATILProcess] {
        if !showGrouped {
            return categorizedProcesses
                .filter { expandedCategories.contains($0.category) }
                .flatMap(\.processes)
        }

        return categorizedProcesses
            .filter { expandedCategories.contains($0.category) }
            .flatMap { group in
                let categoryGroups = groupedProcesses[group.category] ?? []
                return categoryGroups.flatMap { processGroup in
                    if processGroup.isGrouped {
                        return expandedGroupIDs.contains(processGroup.id) ? processGroup.processes : []
                    }
                    return processGroup.processes
                }
            }
    }

    func selectAllVisible() {
        selectedProcessIDs = Set(visibleProcesses.map(\.identity))
        selectedProcessID = selectedProcessIDs.count == 1 ? selectedProcessIDs.first : nil
    }

    func clearSelection() {
        selectedProcessIDs.removeAll()
        selectedProcessID = nil
    }

    func killAllSelected() async {
        // Single selection → route through killSelected for launchd confirmation
        if selectedProcessIDs.count == 1 {
            await killSelected()
            return
        }
        for process in selectedProcesses {
            guard !safetyGate.isProtected(process), process.isUserOwned else { continue }
            if let freed = try? await actionService.kill(process: process) {
                sessionKillCount += 1
                sessionMemoryFreed += freed
            }
        }
        clearSelection()
        loadLifetimeStats()
        await monitor.scan()
    }

    func suspendAllSelected() {
        for process in selectedProcesses {
            guard !safetyGate.isProtected(process), process.isUserOwned else { continue }
            try? actionService.suspend(process: process)
        }
        Task { await monitor.scan() }
    }

    func ignoreAllSelected() {
        // Single selection → route through ignoreSelected
        if selectedProcessIDs.count == 1 {
            ignoreSelected()
            return
        }
        for process in selectedProcesses {
            safetyGate.ignore(process)
        }
        clearSelection()
        Task { await monitor.scan() }
    }

    func startMonitoring() {
        monitor.startPolling(interval: TimeInterval(pollingIntervalSeconds))
        Task { await monitor.scan() }
    }

    func stopMonitoring() {
        monitor.stopPolling()
    }

    func requestSearchFocus() {
        searchFocusNonce += 1
    }

    func recentHistory(limit: Int = 100) -> [KillHistoryRecord] {
        (try? killHistoryRepo.recentHistory(limit: limit)) ?? []
    }

    func canRelaunch(_ record: KillHistoryRecord) -> Bool {
        guard record.isSuccessfulKill, record.relaunchKind != nil else { return false }
        return record.timestamp >= sessionStartedAt
    }

    // MARK: - Private

    private func loadLifetimeStats() {
        lifetimeKills = (try? statsRepo.totalKills()) ?? 0
        lifetimeMemoryFreed = (try? statsRepo.totalMemoryFreed()) ?? 0
    }

    private func loadPreferences() {
        showGrouped = (try? preferencesRepo.bool(forKey: "showGrouped", defaultValue: true)) ?? true
        pollingIntervalSeconds = (try? preferencesRepo.int(forKey: "pollingIntervalSeconds", defaultValue: 60)) ?? 60
    }
}
