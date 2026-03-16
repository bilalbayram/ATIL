import AppKit
import SwiftUI

enum StartupFilter: String, CaseIterable, Identifiable, Sendable {
    case enabled
    case blocked
    case system
    case needsHelper
    case running
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .enabled: "Enabled"
        case .blocked: "Blocked"
        case .system: "System"
        case .needsHelper: "Needs Helper"
        case .running: "Running Now"
        case .unknown: "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .enabled: "power"
        case .blocked: "shield.slash"
        case .system: "lock.shield"
        case .needsHelper: "exclamationmark.key.fill"
        case .running: "waveform.path.ecg"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .enabled: .green
        case .blocked: .red
        case .system: .blue
        case .needsHelper: .orange
        case .running: .mint
        case .unknown: .secondary
        }
    }
}

@Observable
@MainActor
final class StartupItemsViewModel {
    private let processProvider: @MainActor () -> [ATILProcess]
    private let processRefreshAction: @MainActor () async -> Void
    private let inventoryService: StartupInventoryService
    private let controlService: StartupControlService
    private let blockRepository: StartupBlockRepository
    private let actionService = ProcessActionService()

    private var watchers: [DirectoryWatcher] = []
    private var reconciliationTask: Task<Void, Never>?
    private var pendingFocus: StartupItemFocus?

    var items: [StartupItem] = []
    var blockRules: [StartupBlockRule] = []
    var activeFilters: Set<StartupFilter> = []
    var searchText = ""
    var selectedGroupID: String?
    var selectedItemID: String?
    var isRefreshing = false
    var lastError: String?

    init(
        processProvider: @escaping @MainActor () -> [ATILProcess],
        processRefreshAction: @escaping @MainActor () async -> Void,
        inventoryService: StartupInventoryService = StartupInventoryService(),
        controlService: StartupControlService = StartupControlService(),
        blockRepository: StartupBlockRepository = StartupBlockRepository(db: DatabaseManager.shared)
    ) {
        self.processProvider = processProvider
        self.processRefreshAction = processRefreshAction
        self.inventoryService = inventoryService
        self.controlService = controlService
        self.blockRepository = blockRepository
    }

    var filteredItems: [StartupItem] {
        items.filter(matchesSearch).filter(matchesFilters)
    }

    var groups: [StartupAppGroup] {
        Dictionary(grouping: filteredItems, by: \.app)
            .values
            .map { groupedItems in
                let sortedItems = groupedItems.sorted { lhs, rhs in
                    if lhs.state != rhs.state {
                        return lhs.state.rawValue < rhs.state.rawValue
                    }
                    return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
                }

                return StartupAppGroup(
                    app: sortedItems[0].app,
                    items: sortedItems,
                    isBlocked: sortedItems.contains(where: isBlocked)
                )
            }
            .sorted { $0.app.displayName.localizedCaseInsensitiveCompare($1.app.displayName) == .orderedAscending }
    }

    var selectedGroup: StartupAppGroup? {
        if let selectedGroupID {
            return groups.first { $0.id == selectedGroupID }
        }
        return groups.first
    }

    var selectedItem: StartupItem? {
        guard let group = selectedGroup else { return nil }
        if let selectedItemID, let selected = group.items.first(where: { $0.id == selectedItemID }) {
            return selected
        }
        return group.items.first
    }

    var selectedRunningProcess: ATILProcess? {
        guard let item = selectedItem else { return nil }
        let processes = processProvider()
        return item.matchedProcessIDs.lazy.compactMap { pid in
            processes.first(where: { $0.pid == pid })
        }.first
    }

    var helperInstalled: Bool {
        HelperClient.shared.isHelperInstalled
    }

    func startMonitoring() {
        guard reconciliationTask == nil else { return }

        watchers = LaunchdScanner.searchDirectories.map { path in
            DirectoryWatcher(path: path) { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
        }
        watchers.forEach { $0.start() }

        reconciliationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopMonitoring() {
        reconciliationTask?.cancel()
        reconciliationTask = nil
        watchers.forEach { $0.stop() }
        watchers.removeAll()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        applySnapshot(
            items: inventoryService.scan(processes: processProvider()),
            rules: (try? blockRepository.allRules()) ?? []
        )

        let blockedItems = items.filter { item in
            guard isBlocked(item), item.canDisable else { return false }
            if item.scope == .system && !helperInstalled {
                return false
            }
            return item.state != .disabled || item.isRunning
        }

        guard !blockedItems.isEmpty else { return }

        for item in blockedItems {
            do {
                try await controlService.disable(item)
            } catch {
                lastError = error.localizedDescription
            }
        }

        await processRefreshAction()
        applySnapshot(
            items: inventoryService.scan(processes: processProvider()),
            rules: (try? blockRepository.allRules()) ?? []
        )
    }

    func applySnapshot(items: [StartupItem], rules: [StartupBlockRule]) {
        self.items = items
        self.blockRules = rules
        synchronizeSelection()
    }

    func toggleFilter(_ filter: StartupFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }

    func clearFilters() {
        activeFilters.removeAll()
    }

    func focus(on process: ATILProcess) {
        pendingFocus = StartupItemFocus(
            bundleIdentifier: process.owningAppBundleIdentifier ?? process.bundleIdentifier,
            bundlePath: process.owningAppBundlePath ?? process.bundlePath,
            label: process.launchdJob?.label
        )
    }

    func clearFocus() {
        pendingFocus = nil
    }

    func disableSelectedItem() async {
        guard let item = selectedItem else { return }
        await disable(item)
    }

    func disable(_ item: StartupItem) async {
        guard item.canDisable else {
            lastError = "This startup item cannot be disabled safely."
            return
        }

        do {
            if item.scope == .system && !HelperClient.shared.isHelperInstalled {
                try await HelperClient.shared.installHelper()
            }
            try await controlService.disable(item)
            await processRefreshAction()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func blockSelectedApp() {
        guard let group = selectedGroup else { return }

        do {
            _ = try blockRepository.save(StartupBlockRule(app: group.app, items: group.items))
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unblockSelectedApp() {
        guard let rule = selectedGroup.flatMap(blockRule(for:)) else { return }
        guard let id = rule.id else { return }

        do {
            try blockRepository.delete(ruleID: id)
            Task { await refresh() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func killSelectedProcess() async {
        guard let process = selectedRunningProcess else { return }

        do {
            _ = try await actionService.kill(process: process)
            await processRefreshAction()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revealSelectedItem() {
        guard let item = selectedItem else { return }
        controlService.reveal(item)
    }

    func isBlocked(_ item: StartupItem) -> Bool {
        blockRules.contains { $0.matches(item) }
    }

    func blockRule(for group: StartupAppGroup) -> StartupBlockRule? {
        blockRules.first { rule in
            group.items.contains(where: rule.matches)
        }
    }

    func icon(for group: StartupAppGroup) -> NSImage? {
        if let bundlePath = group.app.bundlePath {
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }
        if let executablePath = group.items.compactMap(\.executablePath).first {
            return NSWorkspace.shared.icon(forFile: executablePath)
        }
        return nil
    }

    private func matchesSearch(_ item: StartupItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return item.displayLabel.lowercased().contains(query)
            || item.app.displayName.lowercased().contains(query)
            || (item.label?.lowercased().contains(query) ?? false)
            || (item.executablePath?.lowercased().contains(query) ?? false)
            || (item.app.bundleIdentifier?.lowercased().contains(query) ?? false)
    }

    private func matchesFilters(_ item: StartupItem) -> Bool {
        guard !activeFilters.isEmpty else { return true }

        return activeFilters.allSatisfy { filter in
            switch filter {
            case .enabled:
                item.state == .enabled || item.state == .running
            case .blocked:
                isBlocked(item)
            case .system:
                item.scope == .system
            case .needsHelper:
                item.requiresHelper && !helperInstalled
            case .running:
                item.isRunning
            case .unknown:
                item.state == .unknown
            }
        }
    }

    private func synchronizeSelection() {
        if let pendingFocus {
            applyFocus(pendingFocus)
            self.pendingFocus = nil
            return
        }

        if let selectedGroupID, !groups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = groups.first?.id
        } else if self.selectedGroupID == nil {
            self.selectedGroupID = groups.first?.id
        }

        if let selectedItemID, !(selectedGroup?.items.contains { $0.id == selectedItemID } ?? false) {
            self.selectedItemID = selectedGroup?.items.first?.id
        } else if self.selectedItemID == nil {
            self.selectedItemID = selectedGroup?.items.first?.id
        }
    }

    private func applyFocus(_ focus: StartupItemFocus) {
        let focusedGroup = groups.first { group in
            if let bundleIdentifier = focus.bundleIdentifier, group.app.bundleIdentifier == bundleIdentifier {
                return true
            }
            if let bundlePath = focus.bundlePath, group.app.bundlePath == bundlePath {
                return true
            }
            if let label = focus.label, group.items.contains(where: { $0.label == label }) {
                return true
            }
            return false
        }

        selectedGroupID = focusedGroup?.id ?? groups.first?.id
        selectedItemID = focus.label.flatMap { label in
            focusedGroup?.items.first(where: { $0.label == label })?.id
        } ?? focusedGroup?.items.first?.id ?? groups.first?.items.first?.id
    }
}
