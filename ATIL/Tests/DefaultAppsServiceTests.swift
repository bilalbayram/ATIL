import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ATIL

struct DefaultAppsServiceTests {
    @Test @MainActor func resolvesCurrentHandlersForSchemeAndContentType() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safariURL = try makeTestAppBundle(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            directory: directory
        )
        let textEditURL = try makeTestAppBundle(
            name: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            directory: directory
        )

        let workspace = FakeDefaultAppsWorkspace()
        workspace.urlHandlers["http"] = safariURL
        workspace.urlHandlers["https"] = safariURL
        workspace.urlCandidates["http"] = [safariURL]
        workspace.urlCandidates["https"] = [safariURL]
        workspace.contentHandlers["public.plain-text"] = textEditURL
        workspace.contentCandidates["public.plain-text"] = [textEditURL]

        let service = DefaultAppsService(workspace: workspace)

        let browserState = try service.state(for: .browser)
        let textState = try service.state(for: .plainText)

        #expect(browserState.selectedAppID == "com.apple.Safari")
        #expect(browserState.currentDisplayName == "Safari")
        #expect(textState.selectedAppID == "com.apple.TextEdit")
        #expect(textState.currentDisplayName == "TextEdit")
    }

    @Test @MainActor func candidateListIsDedupedAndSorted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let betaURL = try makeTestAppBundle(
            name: "Beta",
            bundleIdentifier: "com.example.beta",
            directory: directory
        )
        let alphaURL = try makeTestAppBundle(
            name: "Alpha",
            bundleIdentifier: "com.example.alpha",
            directory: directory
        )

        let workspace = FakeDefaultAppsWorkspace()
        workspace.urlHandlers["http"] = betaURL
        workspace.urlHandlers["https"] = betaURL
        workspace.urlCandidates["http"] = [betaURL, alphaURL]
        workspace.urlCandidates["https"] = [alphaURL, betaURL]

        let service = DefaultAppsService(workspace: workspace)
        let state = try service.state(for: .browser)

        #expect(state.candidates.map(\.displayName) == ["Alpha", "Beta"])
    }

    @Test @MainActor func markdownCategoryResolvesFromFilenameExtension() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let textEditURL = try makeTestAppBundle(
            name: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            directory: directory
        )
        let markdownType = try #require(UTType(filenameExtension: "md"))

        let workspace = FakeDefaultAppsWorkspace()
        workspace.contentHandlers[markdownType.identifier] = textEditURL
        workspace.contentCandidates[markdownType.identifier] = [textEditURL]

        let service = DefaultAppsService(workspace: workspace)
        let state = try service.state(for: .markdown)

        #expect(state.selectedAppID == "com.apple.TextEdit")
        #expect(state.currentDisplayName == "TextEdit")
        #expect(state.candidates.map(\.displayName) == ["TextEdit"])
    }

    @Test @MainActor func browserApplyUpdatesHttpThenHttps() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safariURL = try makeTestAppBundle(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            directory: directory
        )
        let chromeURL = try makeTestAppBundle(
            name: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            directory: directory
        )

        let chrome = DefaultAppOption(
            appURL: chromeURL,
            bundleIdentifier: "com.google.Chrome",
            displayName: "Chrome"
        )
        let workspace = FakeDefaultAppsWorkspace()
        workspace.urlHandlers["http"] = safariURL
        workspace.urlHandlers["https"] = safariURL
        workspace.urlCandidates["http"] = [safariURL, chromeURL]
        workspace.urlCandidates["https"] = [safariURL, chromeURL]

        let service = DefaultAppsService(workspace: workspace)
        let result = try await service.apply(chrome, to: .browser)

        #expect(workspace.setCalls == ["scheme:http", "scheme:https"])
        #expect(result.error == nil)
        #expect(result.state.selectedAppID == "com.google.Chrome")
    }

    @Test @MainActor func partialBrowserApplyReloadsStateAndReturnsError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safariURL = try makeTestAppBundle(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            directory: directory
        )
        let chromeURL = try makeTestAppBundle(
            name: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            directory: directory
        )
        let chrome = DefaultAppOption(
            appURL: chromeURL,
            bundleIdentifier: "com.google.Chrome",
            displayName: "Chrome"
        )

        let workspace = FakeDefaultAppsWorkspace()
        workspace.urlHandlers["http"] = safariURL
        workspace.urlHandlers["https"] = safariURL
        workspace.urlCandidates["http"] = [safariURL, chromeURL]
        workspace.urlCandidates["https"] = [safariURL, chromeURL]
        workspace.setFailures["scheme:https"] = DefaultAppsTestError(message: "Consent denied")

        let service = DefaultAppsService(workspace: workspace)
        let result = try await service.apply(chrome, to: .browser)

        #expect(workspace.setCalls == ["scheme:http", "scheme:https"])
        #expect(result.error != nil)
        #expect(result.state.currentSelection == .multiple)
        #expect(result.state.selectedAppID == nil)
        #expect(result.state.currentDisplayName == "Multiple Apps")
    }
}
