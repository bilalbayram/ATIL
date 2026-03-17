import Foundation
import ServiceManagement

/// Client for communicating with the privileged helper tool via XPC.
@MainActor
final class HelperClient {
    static let shared = HelperClient()

    private let helperLabel = "com.bilalbayram.ATIL.Helper"
    private let helperPlistName = "com.bilalbayram.ATIL.Helper.plist"
    private(set) var isHelperInstalled = false

    init() {
        checkHelperStatus()
    }

    // MARK: - Helper Installation

    func checkHelperStatus() {
        let service = SMAppService.daemon(plistName: helperPlistName)
        isHelperInstalled = service.status == .enabled
    }

    func installHelper() async throws {
        let service = SMAppService.daemon(plistName: helperPlistName)
        try service.register()
        isHelperInstalled = true
    }

    // MARK: - XPC Connection

    private func connection() -> NSXPCConnection? {
        guard isHelperInstalled else { return nil }
        let conn = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: ATILHelperProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: ATILAppProtocol.self)

        let appDelegate = AppXPCDelegate()
        conn.exportedObject = appDelegate

        conn.resume()
        return conn
    }

    // MARK: - Privileged Operations

    /// Kill a process owned by another user (requires helper).
    func sendSignal(_ signal: Int32, toPID pid: Int32) async throws -> Bool {
        guard let conn = connection() else {
            throw HelperError.helperNotInstalled
        }
        defer { conn.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let helper = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! ATILHelperProtocol

            helper.sendSignal(signal, toPID: pid) { success, errorMessage in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: HelperError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Disable a launchd job via the privileged helper.
    func disableLaunchdJob(label: String, domain: String = "system") async throws {
        guard let conn = connection() else {
            throw HelperError.helperNotInstalled
        }
        defer { conn.invalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let helper = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! ATILHelperProtocol

            helper.disableLaunchdJob(label: label, domain: domain) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Boot out a launchd job via the privileged helper.
    func bootoutLaunchdJob(label: String, domain: String = "system") async throws {
        guard let conn = connection() else {
            throw HelperError.helperNotInstalled
        }
        defer { conn.invalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let helper = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! ATILHelperProtocol

            helper.bootoutLaunchdJob(label: label, domain: domain) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Enable a launchd job via the privileged helper.
    func enableLaunchdJob(label: String, domain: String, plistPath: String) async throws {
        guard let conn = connection() else {
            throw HelperError.helperNotInstalled
        }
        defer { conn.invalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let helper = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! ATILHelperProtocol

            helper.enableLaunchdJob(label: label, domain: domain, plistPath: plistPath) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Delete a plist file via the privileged helper (system scope only).
    func deletePlistFile(atPath path: String) async throws {
        guard let conn = connection() else {
            throw HelperError.helperNotInstalled
        }
        defer { conn.invalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let helper = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! ATILHelperProtocol

            helper.deletePlistFile(atPath: path) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HelperError.operationFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    // MARK: - Errors

    enum HelperError: Error, LocalizedError {
        case helperNotInstalled
        case operationFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperNotInstalled:
                "Privileged helper not installed. Install it from the app menu to manage system processes."
            case .operationFailed(let msg):
                "Helper operation failed: \(msg)"
            }
        }
    }
}

/// Handles callbacks from the helper to the app.
private class AppXPCDelegate: NSObject, ATILAppProtocol {
    func getVersion(withReply reply: @escaping (String) -> Void) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        reply(version)
    }
}
