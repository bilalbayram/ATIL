import Foundation

/// Protocol defining the narrow XPC API for the privileged helper.
/// The helper only exposes bounded operations — no generic root shell.
@objc protocol ATILHelperProtocol {
    /// Send a signal to a process owned by any user.
    func sendSignal(_ signal: Int32, toPID pid: Int32, withReply reply: @escaping (Bool, String?) -> Void)

    /// Disable a launchd job (bootout/disable).
    func disableLaunchdJob(label: String, domain: String, withReply reply: @escaping (Bool, String?) -> Void)

    /// Enable a launchd job (bootstrap/enable).
    func enableLaunchdJob(label: String, plistPath: String, withReply reply: @escaping (Bool, String?) -> Void)

    /// Read launchd job metadata for a given label.
    func getLaunchdJobInfo(label: String, withReply reply: @escaping (Data?) -> Void)
}

/// The main app's side — the helper can call back to verify the connection.
@objc protocol ATILAppProtocol {
    func getVersion(withReply reply: @escaping (String) -> Void)
}
