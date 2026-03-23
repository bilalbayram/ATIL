import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ATIL

struct DefaultAppsTestError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class FakeDefaultAppsWorkspace: DefaultAppsWorkspace {
    var urlHandlers: [String: URL] = [:]
    var urlCandidates: [String: [URL]] = [:]
    var contentHandlers: [String: URL] = [:]
    var contentCandidates: [String: [URL]] = [:]
    var setFailures: [String: Error] = [:]
    var setCalls: [String] = []

    func urlForApplicationToOpenURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme else { return nil }
        return urlHandlers[scheme]
    }

    func urlsForApplicationsToOpenURL(_ url: URL) -> [URL] {
        guard let scheme = url.scheme else { return [] }
        return urlCandidates[scheme] ?? []
    }

    func urlForApplicationToOpenContentType(_ contentType: UTType) -> URL? {
        contentHandlers[contentType.identifier]
    }

    func urlsForApplicationsToOpenContentType(_ contentType: UTType) -> [URL] {
        contentCandidates[contentType.identifier] ?? []
    }

    func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String) async throws {
        setCalls.append("scheme:\(urlScheme)")
        if let error = setFailures["scheme:\(urlScheme)"] {
            throw error
        }
        urlHandlers[urlScheme] = applicationURL
    }

    func setDefaultApplication(at applicationURL: URL, toOpenContentType contentType: UTType) async throws {
        setCalls.append("type:\(contentType.identifier)")
        if let error = setFailures["type:\(contentType.identifier)"] {
            throw error
        }
        contentHandlers[contentType.identifier] = applicationURL
    }
}

@MainActor
final class FakeDefaultAppsService: DefaultAppsServicing {
    var statesToReturn: [DefaultAppCategoryState]
    var applyCalls: [(category: DefaultAppCategory, optionID: String)] = []
    var applyHandler: ((DefaultAppOption, DefaultAppCategory) async throws -> DefaultAppApplyResult)?

    init(states: [DefaultAppCategoryState]) {
        self.statesToReturn = states
    }

    func states() throws -> [DefaultAppCategoryState] {
        statesToReturn
    }

    func state(for category: DefaultAppCategory) throws -> DefaultAppCategoryState {
        statesToReturn.first { $0.category == category }
            ?? DefaultAppCategoryState(category: category, currentSelection: .none, candidates: [])
    }

    func apply(_ option: DefaultAppOption, to category: DefaultAppCategory) async throws -> DefaultAppApplyResult {
        applyCalls.append((category, option.id))
        if let applyHandler {
            return try await applyHandler(option, category)
        }
        return DefaultAppApplyResult(state: try state(for: category), error: nil)
    }
}

func makeDefaultAppOption(
    name: String = "Safari",
    bundleIdentifier: String = "com.apple.Safari",
    path: String? = nil
) -> DefaultAppOption {
    let resolvedPath = path ?? "/Applications/\(name.replacingOccurrences(of: " ", with: "")).app"
    return DefaultAppOption(
        appURL: URL(fileURLWithPath: resolvedPath),
        bundleIdentifier: bundleIdentifier,
        displayName: name
    )
}

func makeDefaultAppState(
    category: DefaultAppCategory,
    currentSelection: DefaultAppCurrentSelection = .none,
    candidates: [DefaultAppOption] = []
) -> DefaultAppCategoryState {
    DefaultAppCategoryState(
        category: category,
        currentSelection: currentSelection,
        candidates: candidates
    )
}

func makeAllDefaultAppStates(
    overrides: [DefaultAppCategory: DefaultAppCategoryState] = [:]
) -> [DefaultAppCategoryState] {
    DefaultAppCategory.allCases.map { category in
        overrides[category] ?? makeDefaultAppState(category: category)
    }
}

func makeTestAppBundle(
    name: String,
    bundleIdentifier: String,
    directory: URL
) throws -> URL {
    let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

    let plist: [String: Any] = [
        "CFBundleDisplayName": name,
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleName": name,
        "CFBundlePackageType": "APPL"
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

    return appURL
}
