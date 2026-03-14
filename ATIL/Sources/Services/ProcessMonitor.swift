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

    // Carry-forward state for idle tracking
    private var previousIdleTimes: [ProcessIdentity: Date] = [:]
    private var previousCPUTimes: [ProcessIdentity: TimeInterval] = [:]

    // Cached launchd map — refreshed each scan
    private(set) var launchdMap: [String: LaunchdJobInfo] = [:]

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let idleTimes = previousIdleTimes
        let cpuTimes = previousCPUTimes
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
                launchdMap: launchdMap
            )

            return (enumerator.enumerateAll(context: context), launchdMap)
        }.value

        launchdMap = rawProcesses.1

        // Classify on main actor (SafetyGate is MainActor-isolated)
        let classified = rawProcesses.0.map { classifier.classify($0, safetyGate: safetyGate) }

        // Update carry-forward state
        var newIdleTimes: [ProcessIdentity: Date] = [:]
        var newCPUTimes: [ProcessIdentity: TimeInterval] = [:]
        for p in classified {
            if let idle = p.idleSince {
                newIdleTimes[p.identity] = idle
            }
            newCPUTimes[p.identity] = p.cpuTimeTotal
        }
        previousIdleTimes = newIdleTimes
        previousCPUTimes = newCPUTimes

        snapshot = classified

        // Evaluate auto-action rules
        lastRuleResults = await ruleEngine.evaluate(processes: classified)
        if !lastRuleResults.isEmpty {
            // Re-scan to reflect rule actions
            // Don't recurse — just refresh the snapshot
        }
    }

    /// Smart polling: adapts interval based on activity.
    /// Base: 60s idle, shorter if rules fired or user is active.
    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                // Adaptive: shorter interval if rules fired recently
                let nextInterval = (self?.lastRuleResults.isEmpty ?? true) ? interval : max(interval / 6, 10)
                try? await Task.sleep(for: .seconds(nextInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
