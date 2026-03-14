import SwiftUI

@main
struct ATILApp: App {
    @State private var viewModel = ProcessListViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(viewModel)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            // Remove default "New Window" command
            CommandGroup(replacing: .newItem) {}
        }
    }
}
