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

    private var pollingTask: Task<Void, Never>?

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
    }

    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
