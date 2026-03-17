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
        case .needsHelper: "key.fill"
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

enum StartupActionFeedbackStyle: Sendable {
    case progress
    case success
}

struct StartupActionFeedback: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let style: StartupActionFeedbackStyle
}

@Observable
@MainActor
final class StartupItemsViewModel {
    private struct StartupRefreshSnapshot: Sendable {
        let items: [StartupItem]
        let rules: [StartupBlockRule]
    }

    private let processProvider: @MainActor () -> [ATILProcess]
    private let processRefreshAction: @MainActor () async -> Void
    private let inventoryService: StartupInventoryService
    private let controlService: StartupControlService
    private let blockRepository: StartupBlockRepository
    private let actionService = ProcessActionService()

    private var watchers: [DirectoryWatcher] = []
    private var reconciliationTask: Task<Void, Never>?
    private var pendingFocus: StartupItemFocus?
    private var iconCache: [String: NSImage] = [:]
    private var loadingIconKeys: Set<String> = []
    private var hasLoadedSnapshot = false
    private var feedbackResetTask: Task<Void, Never>?

    var items: [StartupItem] = []
    var blockRules: [StartupBlockRule] = []
    var activeFilters: Set<StartupFilter> = []
    var searchText = ""
    var selectedGroupID: String?
    var selectedItemID: String?
    var isRefreshing = false
    var isPerformingUserAction = false
    var actionFeedback: StartupActionFeedback?
    var lastError: String?
    var itemPendingDeletion: StartupItem?
    var showingOrphanWizard = false
    var orphanedItems: [OrphanedStartupItem] = []
    var orphanScanInProgress = false

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

    var isLoadingInitialSnapshot: Bool {
        isRefreshing && !hasLoadedSnapshot && items.isEmpty
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

        let initialSnapshot = await loadSnapshot(
            processes: processProvider(),
            runningApplicationPaths: Set(
                NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
            )
        )
        applySnapshot(items: initialSnapshot.items, rules: initialSnapshot.rules)

        let blockedItems = initialSnapshot.items.filter { item in
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
        let refreshedSnapshot = await loadSnapshot(
            processes: processProvider(),
            runningApplicationPaths: Set(
                NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
            )
        )
        applySnapshot(items: refreshedSnapshot.items, rules: refreshedSnapshot.rules)
    }

    func applySnapshot(items: [StartupItem], rules: [StartupBlockRule]) {
        self.items = items
        self.blockRules = rules
        hasLoadedSnapshot = true
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

        await performUserAction(
            progress: "Disabling \(item.displayLabel)…",
            success: "Disabled \(item.displayLabel)."
        ) {
            if item.scope == .system && !HelperClient.shared.isHelperInstalled {
                try await HelperClient.shared.installHelper()
            }
            try await controlService.disable(item)
            await processRefreshAction()
            await refresh()
        }
    }

    func refreshManually() async {
        await performUserAction(
            progress: "Refreshing startup items…",
            success: "Startup items updated."
        ) {
            await refresh()
        }
    }

    func blockSelectedApp() async {
        guard let group = selectedGroup else { return }

        await performUserAction(
            progress: "Blocking \(group.app.displayName)…",
            success: "Blocked \(group.app.displayName)."
        ) {
            _ = try blockRepository.save(StartupBlockRule(app: group.app, items: group.items))
            await refresh()
        }
    }

    func unblockSelectedApp() async {
        guard let rule = selectedGroup.flatMap(blockRule(for:)) else { return }
        guard let id = rule.id else { return }

        await performUserAction(
            progress: "Removing startup block…",
            success: "Startup block removed."
        ) {
            try blockRepository.delete(ruleID: id)
            await refresh()
        }
    }

    func killSelectedProcess() async {
        guard let process = selectedRunningProcess else { return }

        await performUserAction(
            progress: "Killing \(process.name)…",
            success: "Stopped \(process.name)."
        ) {
            _ = try await actionService.kill(process: process)
            await processRefreshAction()
            await refresh()
        }
    }

    func confirmDeleteSelectedItem() {
        itemPendingDeletion = selectedItem
    }

    func deleteConfirmedItem() async {
        guard let item = itemPendingDeletion else { return }
        itemPendingDeletion = nil

        await performUserAction(
            progress: "Deleting \(item.displayLabel)…",
            success: "Deleted \(item.displayLabel)."
        ) {
            if item.scope == .system && !HelperClient.shared.isHelperInstalled {
                try await HelperClient.shared.installHelper()
            }
            try await controlService.deletePlist(item)
            await processRefreshAction()
            await refresh()
        }
    }

    func scanForOrphans() async {
        orphanScanInProgress = true
        let currentItems = items
        let detectionService = OrphanDetectionService()

        orphanedItems = await Task.detached(priority: .userInitiated) {
            detectionService.detectOrphans(in: currentItems)
        }.value

        orphanScanInProgress = false
        showingOrphanWizard = true
    }

    func deleteOrphanedItems(selected: Set<String>) async {
        let orphansToDelete = orphanedItems.filter { selected.contains($0.id) }
        guard !orphansToDelete.isEmpty else { return }

        await performUserAction(
            progress: "Removing \(orphansToDelete.count) orphaned item(s)…",
            success: "Removed \(orphansToDelete.count) orphaned item(s)."
        ) {
            for orphan in orphansToDelete {
                if orphan.item.scope == .system && !HelperClient.shared.isHelperInstalled {
                    try await HelperClient.shared.installHelper()
                }
                try await controlService.deletePlist(orphan.item)
            }
            await processRefreshAction()
            await refresh()
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
        guard let request = iconRequest(for: group) else { return nil }
        return iconCache[request.cacheKey]
    }

    func loadIconIfNeeded(for group: StartupAppGroup) {
        guard let request = iconRequest(for: group),
              iconCache[request.cacheKey] == nil,
              !loadingIconKeys.contains(request.cacheKey)
        else {
            return
        }

        loadingIconKeys.insert(request.cacheKey)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()

            let icon = NSWorkspace.shared.icon(forFile: request.path)
            self.iconCache[request.cacheKey] = icon
            self.loadingIconKeys.remove(request.cacheKey)
        }
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

    private func loadSnapshot(
        processes: [ATILProcess],
        runningApplicationPaths: Set<String>
    ) async -> StartupRefreshSnapshot {
        let inventoryService = self.inventoryService
        let blockRepository = self.blockRepository

        return await Task.detached(priority: .userInitiated) {
            StartupRefreshSnapshot(
                items: inventoryService.scan(
                    processes: processes,
                    runningApplicationPaths: runningApplicationPaths
                ),
                rules: (try? blockRepository.allRules()) ?? []
            )
        }.value
    }

    private func iconRequest(for group: StartupAppGroup) -> (cacheKey: String, path: String)? {
        if let bundlePath = group.app.bundlePath {
            return (bundlePath, bundlePath)
        }
        if let executablePath = group.items.compactMap(\.executablePath).first {
            return (executablePath, executablePath)
        }
        return nil
    }

    private func performUserAction(
        progress: String,
        success: String,
        operation: () async throws -> Void
    ) async {
        guard !isPerformingUserAction else { return }

        feedbackResetTask?.cancel()
        isPerformingUserAction = true
        actionFeedback = StartupActionFeedback(message: progress, style: .progress)

        do {
            try await operation()
            isPerformingUserAction = false
            actionFeedback = StartupActionFeedback(message: success, style: .success)
            scheduleFeedbackReset()
        } catch {
            isPerformingUserAction = false
            actionFeedback = nil
            lastError = error.localizedDescription
        }
    }

    private func scheduleFeedbackReset() {
        feedbackResetTask?.cancel()
        feedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled else { return }
            guard !self.isPerformingUserAction else { return }
            self.actionFeedback = nil
        }
    }
}
