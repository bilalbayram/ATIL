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
        guard process.isUserOwned else { throw ActionError.notUserOwned }

        let pid = process.pid
        let memory = process.residentMemory

        // Check process still exists
        guard Darwin.kill(pid, 0) == 0 else { throw ActionError.processNotFound }

        // Send SIGTERM
        guard Darwin.kill(pid, SIGTERM) == 0 else {
            throw ActionError.signalFailed(errno)
        }

        // Wait up to 5 seconds for graceful exit
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if Darwin.kill(pid, 0) != 0 {
                recordKill(process: process, action: "kill", result: "success", memoryFreed: memory)
                return memory
            }
        }

        // Force kill if still alive
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
            try? await Task.sleep(for: .milliseconds(200))
        }

        let success = Darwin.kill(pid, 0) != 0
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

    /// Relaunch a previously killed process.
    func relaunch(process: ATILProcess) throws {
        // Try app bundle relaunch
        if let bundlePath = process.bundlePath {
            let url = URL(fileURLWithPath: bundlePath)
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }

        // Try launchd relaunch
        if let job = process.launchdJob {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["load", job.plistPath]
            try task.run()
            task.waitUntilExit()
            return
        }

        throw ActionError.relaunchNotSupported
    }

    // MARK: - Private

    private func recordKill(process: ATILProcess, action: String, result: String, memoryFreed: UInt64) {
        // Determine relaunch token
        let relaunchToken = process.bundlePath ?? process.launchdJob?.plistPath

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
            relaunchToken: relaunchToken
        )

        try? killHistoryRepo.record(record)

        if result == "success" && action == "kill" {
            try? statsRepo.incrementKills()
            try? statsRepo.incrementMemoryFreed(by: Int64(memoryFreed))
        }
    }
}
