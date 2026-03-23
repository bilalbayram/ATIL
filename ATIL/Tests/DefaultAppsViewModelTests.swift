import Foundation
import Testing
@testable import ATIL

struct DefaultAppsViewModelTests {
    @Test @MainActor func loadIfNeededPopulatesRowsFromService() async {
        let safari = makeDefaultAppOption(name: "Safari", bundleIdentifier: "com.apple.Safari")
        let browserState = makeDefaultAppState(
            category: .browser,
            currentSelection: .app(safari),
            candidates: [safari]
        )
        let service = FakeDefaultAppsService(states: makeAllDefaultAppStates(overrides: [.browser: browserState]))
        let viewModel = DefaultAppsViewModel(service: service)

        await viewModel.loadIfNeeded()

        let browserRow = try? #require(viewModel.rows.first { $0.category == .browser })
        #expect(browserRow?.currentDisplayName == "Safari")
        #expect(browserRow?.selectedAppID == "com.apple.Safari")
        #expect(browserRow?.isLoading == false)
    }

    @Test @MainActor func selectMarksRowApplyingUntilServiceReturns() async throws {
        let safari = makeDefaultAppOption(name: "Safari", bundleIdentifier: "com.apple.Safari")
        let chrome = makeDefaultAppOption(name: "Chrome", bundleIdentifier: "com.google.Chrome")
        let initialState = makeDefaultAppState(
            category: .browser,
            currentSelection: .app(safari),
            candidates: [safari, chrome]
        )
        let updatedState = makeDefaultAppState(
            category: .browser,
            currentSelection: .app(chrome),
            candidates: [safari, chrome]
        )
        let service = FakeDefaultAppsService(states: makeAllDefaultAppStates(overrides: [.browser: initialState]))

        var continuation: CheckedContinuation<DefaultAppApplyResult, Error>?
        service.applyHandler = { _, _ in
            try await withCheckedThrowingContinuation { (pending: CheckedContinuation<DefaultAppApplyResult, Error>) in
                continuation = pending
            }
        }

        let viewModel = DefaultAppsViewModel(service: service)
        await viewModel.loadIfNeeded()

        let task = Task { await viewModel.select(chrome, for: .browser) }
        await Task.yield()

        let applyingRow = try #require(viewModel.rows.first { $0.category == .browser })
        #expect(applyingRow.isApplying)

        continuation?.resume(returning: DefaultAppApplyResult(state: updatedState, error: nil))
        await task.value

        let finalRow = try #require(viewModel.rows.first { $0.category == .browser })
        #expect(finalRow.isApplying == false)
        #expect(finalRow.currentDisplayName == "Chrome")
        #expect(finalRow.selectedAppID == "com.google.Chrome")
    }

    @Test @MainActor func cancelledApplyKeepsPreviousDefaultVisible() async {
        let safari = makeDefaultAppOption(name: "Safari", bundleIdentifier: "com.apple.Safari")
        let chrome = makeDefaultAppOption(name: "Chrome", bundleIdentifier: "com.google.Chrome")
        let browserState = makeDefaultAppState(
            category: .browser,
            currentSelection: .app(safari),
            candidates: [safari, chrome]
        )
        let service = FakeDefaultAppsService(states: makeAllDefaultAppStates(overrides: [.browser: browserState]))
        service.applyHandler = { _, _ in
            DefaultAppApplyResult(
                state: browserState,
                error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
            )
        }

        let viewModel = DefaultAppsViewModel(service: service)
        await viewModel.loadIfNeeded()
        await viewModel.select(chrome, for: .browser)

        let row = try? #require(viewModel.rows.first { $0.category == .browser })
        #expect(row?.currentDisplayName == "Safari")
        #expect(row?.selectedAppID == "com.apple.Safari")
        #expect(row?.errorMessage == "Change cancelled.")
    }

    @Test @MainActor func unavailableRowsRemainUnavailableAfterLoad() async {
        let unavailableState = makeDefaultAppState(category: .video)
        let service = FakeDefaultAppsService(states: makeAllDefaultAppStates(overrides: [.video: unavailableState]))
        let viewModel = DefaultAppsViewModel(service: service)

        await viewModel.loadIfNeeded()

        let row = try? #require(viewModel.rows.first { $0.category == .video })
        #expect(row?.isUnavailable == true)
        #expect(row?.currentDisplayName == "No Default")
    }
}
