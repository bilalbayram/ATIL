import Darwin
import Foundation

struct ProcessActionService: Sendable {

    enum ActionError: Error, LocalizedError {
        case notUserOwned
        case protectedProcess
        case signalFailed(Int32)
        case processNotFound

        var errorDescription: String? {
            switch self {
            case .notUserOwned: "Cannot signal processes owned by other users"
            case .protectedProcess: "This process is protected and cannot be killed"
            case .signalFailed(let errno): "Signal failed with error code \(errno)"
            case .processNotFound: "Process no longer exists"
            }
        }
    }

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
            if Darwin.kill(pid, 0) != 0 { return memory }
        }

        // Force kill if still alive
        if Darwin.kill(pid, 0) == 0 {
            Darwin.kill(pid, SIGKILL)
            try? await Task.sleep(for: .milliseconds(200))
        }

        return memory
    }

    // v0.3: suspend/resume
    func suspend(pid: pid_t) -> Bool {
        Darwin.kill(pid, SIGSTOP) == 0
    }

    func resume(pid: pid_t) -> Bool {
        Darwin.kill(pid, SIGCONT) == 0
    }
}
