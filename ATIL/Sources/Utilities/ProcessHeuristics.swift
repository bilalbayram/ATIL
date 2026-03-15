import Darwin
import Foundation

enum ProcessHeuristics {
    private static let knownSystemPathPrefixes: [String] = [
        "/usr/sbin/",
        "/usr/libexec/",
        "/System/Library/",
        "/System/Applications/",
        "/sbin/",
    ]

    private static let concreteBundleExtensions: Set<String> = [
        "app",
        "appex",
        "bundle",
        "xpc",
    ]

    static func isKnownSystemPath(_ path: String?) -> Bool {
        guard let path else { return false }
        return knownSystemPathPrefixes.contains { path.hasPrefix($0) }
    }

    static func nearestBundlePath(forExecutablePath path: String) -> String? {
        var url = URL(fileURLWithPath: path)

        while url.path != "/" {
            if concreteBundleExtensions.contains(url.pathExtension.lowercased()) {
                return url.path
            }
            url.deleteLastPathComponent()
        }

        return nil
    }

    static func owningAppBundlePath(forExecutablePath path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        var appPath: String?

        while url.path != "/" {
            if url.pathExtension.lowercased() == "app" {
                appPath = url.path
            }
            url.deleteLastPathComponent()
        }

        return appPath
    }

    static func isLikelyOrphaned(
        ppid: pid_t,
        launchdJob: LaunchdJobInfo?,
        owningAppBundlePath: String?,
        owningAppBundleIdentifier: String?,
        bundlePath: String?,
        bundleIdentifier: String?,
        executablePath: String?
    ) -> Bool {
        ppid == 1
            && launchdJob == nil
            && owningAppBundlePath == nil
            && owningAppBundleIdentifier == nil
            && bundlePath == nil
            && bundleIdentifier == nil
            && !isKnownSystemPath(executablePath)
    }
}
