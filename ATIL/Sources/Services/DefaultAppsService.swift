import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol DefaultAppsWorkspace {
    func urlForApplicationToOpenURL(_ url: URL) -> URL?
    func urlsForApplicationsToOpenURL(_ url: URL) -> [URL]
    func urlForApplicationToOpenContentType(_ contentType: UTType) -> URL?
    func urlsForApplicationsToOpenContentType(_ contentType: UTType) -> [URL]
    func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String) async throws
    func setDefaultApplication(at applicationURL: URL, toOpenContentType contentType: UTType) async throws
}

@MainActor
struct SystemDefaultAppsWorkspace: DefaultAppsWorkspace {
    func urlForApplicationToOpenURL(_ url: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    func urlsForApplicationsToOpenURL(_ url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    func urlForApplicationToOpenContentType(_ contentType: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: contentType)
    }

    func urlsForApplicationsToOpenContentType(_ contentType: UTType) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: contentType)
    }

    func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: urlScheme) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setDefaultApplication(at applicationURL: URL, toOpenContentType contentType: UTType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpen: contentType) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
protocol DefaultAppsServicing {
    func states() throws -> [DefaultAppCategoryState]
    func state(for category: DefaultAppCategory) throws -> DefaultAppCategoryState
    func apply(_ option: DefaultAppOption, to category: DefaultAppCategory) async throws -> DefaultAppApplyResult
}

@MainActor
struct DefaultAppsService: DefaultAppsServicing {
    enum ServiceError: LocalizedError {
        case invalidContentType(String)
        case invalidFilenameExtension(String)

        var errorDescription: String? {
            switch self {
            case .invalidContentType(let identifier):
                "Unsupported content type: \(identifier)"
            case .invalidFilenameExtension(let fileExtension):
                "Unsupported filename extension: \(fileExtension)"
            }
        }
    }

    private let workspace: DefaultAppsWorkspace
    private let fileManager: FileManager

    init(workspace: DefaultAppsWorkspace, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    init() {
        self.init(workspace: SystemDefaultAppsWorkspace())
    }

    func states() throws -> [DefaultAppCategoryState] {
        try DefaultAppCategory.allCases.map(state(for:))
    }

    func state(for category: DefaultAppCategory) throws -> DefaultAppCategoryState {
        let currentApps = try category.targets.compactMap(currentAppOption(for:))
        let candidates = try resolvedCandidates(for: category, including: currentApps)

        let currentSelection: DefaultAppCurrentSelection
        let uniqueCurrentApps = uniqueOptions(currentApps)
        switch uniqueCurrentApps.count {
        case 0:
            currentSelection = .none
        case 1:
            currentSelection = .app(uniqueCurrentApps[0])
        default:
            currentSelection = .multiple
        }

        return DefaultAppCategoryState(
            category: category,
            currentSelection: currentSelection,
            candidates: candidates
        )
    }

    func apply(_ option: DefaultAppOption, to category: DefaultAppCategory) async throws -> DefaultAppApplyResult {
        var applyError: Error?

        for target in category.targets {
            do {
                try await setDefaultApplication(at: option.appURL, for: target)
            } catch {
                applyError = error
                break
            }
        }

        return DefaultAppApplyResult(
            state: try state(for: category),
            error: applyError
        )
    }

    private func currentAppOption(for target: DefaultAppTarget) throws -> DefaultAppOption? {
        switch target {
        case .urlScheme:
            let probeURL = target.probeURL
            guard let applicationURL = workspace.urlForApplicationToOpenURL(probeURL) else { return nil }
            return appOption(for: applicationURL)
        case .contentType, .filenameExtension:
            let contentType = try utType(for: target)
            guard let applicationURL = workspace.urlForApplicationToOpenContentType(contentType) else { return nil }
            return appOption(for: applicationURL)
        }
    }

    private func resolvedCandidates(
        for category: DefaultAppCategory,
        including currentApps: [DefaultAppOption]
    ) throws -> [DefaultAppOption] {
        var options = currentApps

        for target in category.targets {
            let urls = try candidateURLs(for: target)
            options.append(contentsOf: urls.map(appOption(for:)))
        }

        return uniqueOptions(options).sorted {
            let lhsName = $0.displayName.localizedLowercase
            let rhsName = $1.displayName.localizedLowercase
            if lhsName == rhsName {
                return $0.appURL.path < $1.appURL.path
            }
            return lhsName < rhsName
        }
    }

    private func candidateURLs(for target: DefaultAppTarget) throws -> [URL] {
        switch target {
        case .urlScheme:
            let probeURL = target.probeURL
            return workspace.urlsForApplicationsToOpenURL(probeURL)
        case .contentType, .filenameExtension:
            let contentType = try utType(for: target)
            return workspace.urlsForApplicationsToOpenContentType(contentType)
        }
    }

    private func setDefaultApplication(at applicationURL: URL, for target: DefaultAppTarget) async throws {
        switch target {
        case .urlScheme(let scheme):
            try await workspace.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: scheme)
        case .contentType, .filenameExtension:
            let contentType = try utType(for: target)
            try await workspace.setDefaultApplication(at: applicationURL, toOpenContentType: contentType)
        }
    }

    private func utType(for target: DefaultAppTarget) throws -> UTType {
        switch target {
        case .contentType(let identifier):
            guard let contentType = UTType(identifier) else {
                throw ServiceError.invalidContentType(identifier)
            }
            return contentType
        case .filenameExtension(let fileExtension):
            guard let contentType = UTType(filenameExtension: fileExtension) else {
                throw ServiceError.invalidFilenameExtension(fileExtension)
            }
            return contentType
        case .urlScheme:
            fatalError("Only content targets can be resolved to UTType")
        }
    }

    private func appOption(for applicationURL: URL) -> DefaultAppOption {
        let bundle = Bundle(url: applicationURL)
        let bundleDisplayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fileDisplayName = fileManager.displayName(atPath: applicationURL.path)
        let rawDisplayName = bundleDisplayName
            ?? bundleName
            ?? fileDisplayName
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let displayName = rawDisplayName.hasSuffix(".app")
            ? String(rawDisplayName.dropLast(4))
            : rawDisplayName

        return DefaultAppOption(
            appURL: applicationURL,
            bundleIdentifier: bundle?.bundleIdentifier,
            displayName: displayName
        )
    }

    private func uniqueOptions(_ options: [DefaultAppOption]) -> [DefaultAppOption] {
        var seen = Set<String>()
        var result: [DefaultAppOption] = []

        for option in options {
            guard seen.insert(option.id).inserted else { continue }
            result.append(option)
        }

        return result
    }
}

private extension DefaultAppTarget {
    var probeURL: URL {
        switch self {
        case .urlScheme("mailto"):
            URL(string: "mailto:test@example.com")!
        case .urlScheme(let scheme):
            URL(string: "\(scheme)://example.com")!
        case .contentType, .filenameExtension:
            fatalError("Only URL scheme targets have probe URLs")
        }
    }
}
