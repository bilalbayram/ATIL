import Foundation

@Observable
@MainActor
final class ProcessMonitor {
    var snapshot: [ATILProcess] = []
    var isScanning = false

    private let enumerator = ProcessEnumerator()
    private let classifier = ProcessClassifier()
    private let safetyGate = SafetyGate.shared
    private let launchdScanner = LaunchdScanner()
    let ruleEngine = RuleEngine()

    private var pollingTask: Task<Void, Never>?
    var lastRuleResults: [RuleEngine.RuleResult] = []
    var focusedProcessID: ProcessIdentity?

    // Carry-forward state for idle tracking
    private var previousIdleTimes: [ProcessIdentity: Date] = [:]
    private var previousCPUTimes: [ProcessIdentity: TimeInterval] = [:]
    private var previousSeenTimes: [ProcessIdentity: Date] = [:]

    // Cached launchd map — refreshed each scan
    private(set) var launchdMap: [String: LaunchdJobInfo] = [:]

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let idleTimes = previousIdleTimes
        let cpuTimes = previousCPUTimes
        let seenTimes = previousSeenTimes
        let enumerator = self.enumerator
        let launchdScanner = self.launchdScanner

        let rawProcesses = await Task.detached {
            let now = Date()
            let allPIDs = enumerator.listAllPIDs()
            let alivePIDs = Set(allPIDs)
            let launchdMap = launchdScanner.scanAll()

            let context = ProcessEnumerator.EnumerationContext(
                now: now,
                currentUID: getuid(),
                alivePIDs: alivePIDs,
                previousIdleTimes: idleTimes,
                previousCPUTimes: cpuTimes,
                previousSeenTimes: seenTimes,
                launchdMap: launchdMap
            )

            return (enumerator.enumerateAll(context: context), launchdMap)
        }.value

        launchdMap = rawProcesses.1

        let overrides = ruleEngine.categoryOverrides(for: rawProcesses.0)

        // Classify on main actor (SafetyGate is MainActor-isolated)
        let classified = rawProcesses.0.map { process in
            classifier.classify(
                process,
                safetyGate: safetyGate,
                categoryOverride: overrides[process.identity]
            )
        }

        // Update carry-forward state
        var newIdleTimes: [ProcessIdentity: Date] = [:]
        var newCPUTimes: [ProcessIdentity: TimeInterval] = [:]
        var newSeenTimes: [ProcessIdentity: Date] = [:]
        for p in classified {
            if let idle = p.idleSince {
                newIdleTimes[p.identity] = idle
            }
            newCPUTimes[p.identity] = p.cpuTimeTotal
            newSeenTimes[p.identity] = p.lastSeen
        }
        previousIdleTimes = newIdleTimes
        previousCPUTimes = newCPUTimes
        previousSeenTimes = newSeenTimes

        snapshot = classified

        // Evaluate auto-action rules
        lastRuleResults = await ruleEngine.evaluate(processes: classified)
        if !lastRuleResults.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                await self?.scan()
            }
        }
    }

    /// Smart polling: adapts interval based on activity.
    /// Base: 60s idle, shorter if rules fired or user is active.
    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                // Focused watch: selected/suspicious processes are refreshed more frequently.
                let nextInterval: TimeInterval
                if self?.focusedProcessID != nil {
                    nextInterval = 10
                } else if self?.lastRuleResults.isEmpty == false {
                    nextInterval = max(interval / 6, 10)
                } else {
                    nextInterval = interval
                }
                try? await Task.sleep(for: .seconds(nextInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
