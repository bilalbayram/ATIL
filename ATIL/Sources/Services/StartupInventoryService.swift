import Foundation

struct StartupInventoryService: Sendable {
    typealias LaunchdJobsProvider = @Sendable () -> [LaunchdJobInfo]
    typealias DisabledStatesProvider = @Sendable () -> [String: [String: Bool]]
    typealias DiscoveryProvider = @Sendable () -> StartupDiscoveryContext
    typealias CuratedAttributionsProvider = @Sendable () -> [String: CuratedStartupAttribution]

    private let launchdJobsProvider: LaunchdJobsProvider
    private let disabledStatesProvider: DisabledStatesProvider
    private let discoveryProvider: DiscoveryProvider
    private let curatedAttributionsProvider: CuratedAttributionsProvider
    private let attributionService: StartupAttributionService

    init(
        launchdJobsProvider: @escaping LaunchdJobsProvider = { LaunchdScanner().scanJobs() },
        disabledStatesProvider: @escaping DisabledStatesProvider = { LaunchdDisabledStateReader().readDisabledStates() },
        discoveryProvider: @escaping DiscoveryProvider = { StartupAttributionService().discoverContext() },
        curatedAttributionsProvider: @escaping CuratedAttributionsProvider = { StartupAttributionService().curatedAttributions() },
        attributionService: StartupAttributionService = StartupAttributionService()
    ) {
        self.launchdJobsProvider = launchdJobsProvider
        self.disabledStatesProvider = disabledStatesProvider
        self.discoveryProvider = discoveryProvider
        self.curatedAttributionsProvider = curatedAttributionsProvider
        self.attributionService = attributionService
    }

    func scan(processes: [ATILProcess], runningApplicationPaths: Set<String>? = nil) -> [StartupItem] {
        let jobs = launchdJobsProvider()
        let disabledStates = disabledStatesProvider()
        let discovery = runningApplicationPaths.map(attributionService.discoverContext(runningApplicationPaths:))
            ?? discoveryProvider()
        let curatedAttributions = curatedAttributionsProvider()

        var items: [StartupItem] = jobs.map { job in
            buildLaunchdItem(
                job: job,
                disabledStates: disabledStates,
                discovery: discovery,
                curatedAttributions: curatedAttributions,
                processes: processes
            )
        }

        let knownLabels = Set(items.compactMap(\.label))
        let loginHelpersByBundleID: [String: DiscoveredLoginItem] = Dictionary(
            uniqueKeysWithValues: discovery.loginItems.compactMap { helper in
                guard let bundleIdentifier = helper.helperBundleIdentifier else { return nil }
                return (bundleIdentifier, helper)
            }
        )

        let guiDomain = "gui/\(getuid())"
        for (label, isDisabled) in disabledStates[guiDomain] ?? [:] where !knownLabels.contains(label) {
            let helper = loginHelpersByBundleID[label]
            let curated = curatedAttributions[label]
            guard helper != nil || curated != nil else { continue }

            let executablePath = helper?.helperExecutablePath
            let attribution = attributionService.resolve(
                label: label,
                executablePath: executablePath,
                discovery: discovery,
                loginItem: helper,
                curatedAttribution: curated
            )
            let matchedProcesses = matchingProcesses(
                label: label,
                executablePath: executablePath,
                processes: processes
            )
            let state = runtimeState(disabled: isDisabled, matchedProcesses: matchedProcesses, defaultState: .enabled)

            items.append(
                StartupItem(
                    id: "synthetic:\(guiDomain):\(label)",
                    kind: helper == nil ? .backgroundHelper : .loginItem,
                    scope: .user,
                    state: state,
                    label: label,
                    plistPath: nil,
                    executablePath: executablePath,
                    programArguments: executablePath.map { [$0] } ?? [],
                    domain: guiDomain,
                    app: attribution.app,
                    attributionConfidence: attribution.confidence,
                    attributionSources: attribution.sources,
                    matchedProcessIDs: matchedProcesses.map(\ATILProcess.pid),
                    matchedProcessNames: matchedProcesses.map(\ATILProcess.name)
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.app.displayName != rhs.app.displayName {
                return lhs.app.displayName.localizedCaseInsensitiveCompare(rhs.app.displayName) == .orderedAscending
            }
            return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
        }
    }

    private func buildLaunchdItem(
        job: LaunchdJobInfo,
        disabledStates: [String: [String: Bool]],
        discovery: StartupDiscoveryContext,
        curatedAttributions: [String: CuratedStartupAttribution],
        processes: [ATILProcess]
    ) -> StartupItem {
        let isDisabled = disabledStates[job.domain]?[job.label] ?? false
        let loginItem = discovery.loginItems.first { helper in
            helper.helperExecutablePath == job.programPath || helper.helperBundleIdentifier == job.label
        }
        let attribution = attributionService.resolve(
            label: job.label,
            executablePath: job.programPath,
            discovery: discovery,
            loginItem: loginItem,
            curatedAttribution: curatedAttributions[job.label]
        )
        let matchedProcesses = matchingProcesses(
            label: job.label,
            executablePath: job.programPath,
            processes: processes
        )

        let defaultState: StartupItemState = isDisabled ? .disabled : .enabled

        return StartupItem(
            id: "launchd:\(job.domain):\(job.label)",
            kind: job.scope == .system ? .launchDaemon : .launchAgent,
            scope: job.scope,
            state: runtimeState(disabled: isDisabled, matchedProcesses: matchedProcesses, defaultState: defaultState),
            label: job.label,
            plistPath: job.plistPath,
            executablePath: job.programPath,
            programArguments: job.programArguments ?? [],
            domain: job.domain,
            app: attribution.app,
            attributionConfidence: attribution.confidence,
            attributionSources: attribution.sources,
            matchedProcessIDs: matchedProcesses.map(\.pid),
            matchedProcessNames: matchedProcesses.map(\.name)
        )
    }

    private func runtimeState(
        disabled: Bool,
        matchedProcesses: [ATILProcess],
        defaultState: StartupItemState
    ) -> StartupItemState {
        if !matchedProcesses.isEmpty {
            return .running
        }
        return disabled ? .disabled : defaultState
    }

    private func matchingProcesses(
        label: String?,
        executablePath: String?,
        processes: [ATILProcess]
    ) -> [ATILProcess] {
        processes.filter { process in
            if let label, process.launchdJob?.label == label {
                return true
            }
            if let executablePath, process.executablePath == executablePath {
                return true
            }
            return false
        }
    }
}
