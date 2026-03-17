import AppKit
import Foundation

struct StartupControlService: Sendable {
    enum ControlError: Error, LocalizedError {
        case unsupportedItem
        case launchctlFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedItem:
                "This startup item cannot be controlled safely."
            case .launchctlFailed(let message):
                message
            }
        }
    }

    func disable(_ item: StartupItem) async throws {
        guard let label = item.label else { throw ControlError.unsupportedItem }

        if item.scope == .system {
            try await HelperClient.shared.disableLaunchdJob(label: label, domain: item.domain)
            try await HelperClient.shared.bootoutLaunchdJob(label: label, domain: item.domain)
            return
        }

        try runLaunchctl(arguments: ["disable", "\(item.domain)/\(label)"])

        if let plistPath = item.plistPath {
            try? runLaunchctl(arguments: ["bootout", item.domain, plistPath])
        } else {
            try? runLaunchctl(arguments: ["bootout", "\(item.domain)/\(label)"])
        }
    }

    func deletePlist(_ item: StartupItem) async throws {
        guard let plistPath = item.plistPath else { throw ControlError.unsupportedItem }

        // Bootout the job first if it has a label
        if let label = item.label {
            if item.scope == .system {
                try? await HelperClient.shared.bootoutLaunchdJob(label: label, domain: item.domain)
                try? await HelperClient.shared.disableLaunchdJob(label: label, domain: item.domain)
            } else {
                try? runLaunchctl(arguments: ["bootout", "\(item.domain)/\(label)"])
                try? runLaunchctl(arguments: ["disable", "\(item.domain)/\(label)"])
            }
        }

        // Delete the plist
        if item.scope == .system {
            try await HelperClient.shared.deletePlistFile(atPath: plistPath)
        } else {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: plistPath),
                resultingItemURL: &resultingURL
            )
        }
    }

    func reveal(_ item: StartupItem) {
        guard let path = item.plistPath ?? item.executablePath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    private func runLaunchctl(arguments: [String]) throws {
        let task = Process()
        let errorPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            throw ControlError.launchctlFailed(error.localizedDescription)
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ControlError.launchctlFailed(message?.isEmpty == false ? message! : "launchctl failed")
        }
    }
}
