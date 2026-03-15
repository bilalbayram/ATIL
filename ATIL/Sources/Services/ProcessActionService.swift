import AppKit
import Darwin
import Foundation

struct ProcessActionService: Sendable {

    enum ActionError: Error, LocalizedError {
        case notUserOwned
        case protectedProcess
        case signalFailed(Int32)
        case processNotFound
        case relaunchNotSupported

        var errorDescription: String? {
            switch self {
            case .notUserOwned: "Cannot signal processes owned by other users"
            case .protectedProcess: "This process is protected and cannot be killed"
            case .signalFailed(let errno): "Signal failed with error code \(errno)"
            case .processNotFound: "Process no longer exists"
            case .relaunchNotSupported: "No supported relaunch strategy for this process"
            }
        }
    }

    private let killHistoryRepo = KillHistoryRepository(db: DatabaseManager.shared)
    private let statsRepo = StatsRepository(db: DatabaseManager.shared)

    /// Kill a process: SIGTERM first, then SIGKILL after timeout.
    /// Returns the resident memory of the process (for stats tracking).
    func kill(process: ATILProcess) async throws -> UInt64 {
        let pid = process.pid
        let memory = process.residentMemory
        let usesHelper = !process.isUserOwned

        // Check process still exists
        if usesHelper {
            guard await HelperClient.shared.isHelperInstalled else {
                throw ActionError.notUserOwned
            }
            _ = try await HelperClient.shared.sendSignal(0, toPID: pid)
        } else {
            guard Darwin.kill(pid, 0) == 0 else { throw ActionError.processNotFound }
        }

        // Send SIGTERM
        if usesHelper {
            _ = try await HelperClient.shared.sendSignal(SIGTERM, toPID: pid)
        } else {
            guard Darwin.kill(pid, SIGTERM) == 0 else {
                throw ActionError.signalFailed(errno)
            }
        }

        // Wait up to 5 seconds for graceful exit
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if usesHelper {
                if (try? await HelperClient.shared.sendSignal(0, toPID: pid)) != true {
                    recordKill(process: process, action: "kill", result: "success", memoryFreed: memory)
                    return memory
                }
            } else if Darwin.kill(pid, 0) != 0 {
                recordKill(process: process, action: "kill", result: "success", memoryFreed: memory)
                return memory
            }
        }

        // Force kill if still alive
        if usesHelper {
            _ = try await HelperClient.shared.sendSignal(SIGKILL, toPID: pid)
            try? await Task.sleep(for: .milliseconds(200))
        } else if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
            try? await Task.sleep(for: .milliseconds(200))
        }

        let success: Bool
        if usesHelper {
            success = (try? await HelperClient.shared.sendSignal(0, toPID: pid)) != true
        } else {
            success = Darwin.kill(pid, 0) != 0
        }
        recordKill(
            process: process,
            action: "kill",
            result: success ? "success" : "failed",
            memoryFreed: success ? memory : 0
        )
        return success ? memory : 0
    }

    /// Suspend a process (SIGSTOP).
    func suspend(process: ATILProcess) throws {
        guard process.isUserOwned else { throw ActionError.notUserOwned }
        guard Darwin.kill(process.pid, 0) == 0 else { throw ActionError.processNotFound }
        guard Darwin.kill(process.pid, SIGSTOP) == 0 else {
            throw ActionError.signalFailed(errno)
        }
        recordKill(process: process, action: "suspend", result: "success", memoryFreed: 0)
    }

    /// Resume a suspended process (SIGCONT).
    func resume(pid: pid_t) -> Bool {
        Darwin.kill(pid, SIGCONT) == 0
    }

    /// Relaunch a previously killed process from kill history.
    func relaunch(record: KillHistoryRecord) throws {
        switch record.relaunchKind {
        case .appBundle:
            guard let bundlePath = record.relaunchToken else {
                throw ActionError.relaunchNotSupported
            }
            let url = URL(fileURLWithPath: bundlePath)
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
        case .launchdJob:
            guard let plistPath = record.relaunchToken,
                  let label = record.launchdLabel,
                  let domain = record.launchdDomain
            else {
                throw ActionError.relaunchNotSupported
            }

            let serviceTarget = "\(domain)/\(label)"
            try runLaunchctl(arguments: ["enable", serviceTarget])
            try runLaunchctl(arguments: ["bootstrap", domain, plistPath])
            try? runLaunchctl(arguments: ["kickstart", "-k", serviceTarget])

        case .none:
            throw ActionError.relaunchNotSupported
        }
    }

    // MARK: - Private

    private func recordKill(process: ATILProcess, action: String, result: String, memoryFreed: UInt64) {
        let relaunchKind: KillHistoryRecord.RelaunchKind?
        let relaunchToken: String?
        let launchdLabel: String?
        let launchdDomain: String?

        if let bundlePath = process.bundlePath {
            relaunchKind = .appBundle
            relaunchToken = bundlePath
            launchdLabel = nil
            launchdDomain = nil
        } else if let job = process.launchdJob {
            relaunchKind = .launchdJob
            relaunchToken = job.plistPath
            launchdLabel = job.label
            launchdDomain = job.domain
        } else {
            relaunchKind = nil
            relaunchToken = nil
            launchdLabel = nil
            launchdDomain = nil
        }

        let record = KillHistoryRecord(
            timestamp: Date(),
            pid: process.pid,
            processStartTime: process.startTime,
            processName: process.name,
            executablePath: process.executablePath,
            bundleIdentifier: process.bundleIdentifier,
            action: action,
            result: result,
            memoryFreed: Int64(memoryFreed),
            relaunchToken: relaunchToken,
            relaunchKind: relaunchKind,
            launchdLabel: launchdLabel,
            launchdDomain: launchdDomain
        )

        try? killHistoryRepo.record(record)

        if result == "success" && action == "kill" {
            try? statsRepo.incrementKills()
            try? statsRepo.incrementMemoryFreed(by: Int64(memoryFreed))
        }
    }

    private func runLaunchctl(arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw ActionError.relaunchNotSupported
        }
    }
}
