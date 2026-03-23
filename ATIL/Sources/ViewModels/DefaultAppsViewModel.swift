import Foundation

struct DefaultAppRowState: Identifiable, Equatable {
    let category: DefaultAppCategory
    var currentSelection: DefaultAppCurrentSelection
    var candidates: [DefaultAppOption]
    var isLoading: Bool
    var isApplying: Bool
    var errorMessage: String?

    var id: String { category.id }

    var selectedAppID: String? {
        guard case .app(let app) = currentSelection else { return nil }
        return app.id
    }

    var currentDisplayName: String {
        switch currentSelection {
        case .none:
            "No Default"
        case .app(let app):
            app.displayName
        case .multiple:
            "Multiple Apps"
        }
    }

    var currentIconPath: String? {
        guard case .app(let app) = currentSelection else { return nil }
        return app.appURL.path
    }

    var isUnavailable: Bool {
        candidates.isEmpty
    }

    init(category: DefaultAppCategory) {
        self.category = category
        self.currentSelection = .none
        self.candidates = []
        self.isLoading = true
        self.isApplying = false
        self.errorMessage = nil
    }

    init(state: DefaultAppCategoryState) {
        self.category = state.category
        self.currentSelection = state.currentSelection
        self.candidates = state.candidates
        self.isLoading = false
        self.isApplying = false
        self.errorMessage = nil
    }
}

@Observable
@MainActor
final class DefaultAppsViewModel {
    private let service: DefaultAppsServicing
    private var hasLoaded = false

    var rows = DefaultAppCategory.allCases.map(DefaultAppRowState.init(category:))
    var lastError: String?

    init(service: DefaultAppsServicing) {
        self.service = service
    }

    init() {
        self.service = DefaultAppsService()
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = await reload()
    }

    @discardableResult
    func reload() async -> Bool {
        lastError = nil
        for index in rows.indices {
            rows[index].isLoading = true
            rows[index].errorMessage = nil
        }

        do {
            let states = try service.states()
            applyLoadedStates(states)
            return true
        } catch {
            lastError = error.localizedDescription
            for index in rows.indices {
                rows[index].isLoading = false
            }
            return false
        }
    }

    func select(_ option: DefaultAppOption, for category: DefaultAppCategory) async {
        guard let index = rowIndex(for: category) else { return }

        rows[index].isApplying = true
        rows[index].errorMessage = nil

        do {
            let result = try await service.apply(option, to: category)
            applyState(result.state, to: index, errorMessage: result.error.map(presentableRowMessage(for:)))
        } catch {
            rows[index].isApplying = false
            rows[index].isLoading = false
            lastError = error.localizedDescription
        }
    }

    private func applyLoadedStates(_ states: [DefaultAppCategoryState]) {
        let statesByCategory = Dictionary(uniqueKeysWithValues: states.map { ($0.category, $0) })
        for index in rows.indices {
            guard let state = statesByCategory[rows[index].category] else {
                rows[index].isLoading = false
                continue
            }
            applyState(state, to: index, errorMessage: nil)
        }
    }

    private func applyState(
        _ state: DefaultAppCategoryState,
        to index: Int,
        errorMessage: String?
    ) {
        rows[index].currentSelection = state.currentSelection
        rows[index].candidates = state.candidates
        rows[index].isLoading = false
        rows[index].isApplying = false
        rows[index].errorMessage = errorMessage
    }

    private func rowIndex(for category: DefaultAppCategory) -> Int? {
        rows.firstIndex { $0.category == category }
    }

    private func presentableRowMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == NSUserCancelledError {
            return "Change cancelled."
        }
        return error.localizedDescription
    }
}
