import SwiftUI

struct FocusedViewModelKey: FocusedValueKey {
    typealias Value = ProcessListViewModel
}

extension FocusedValues {
    var viewModel: ProcessListViewModel? {
        get { self[FocusedViewModelKey.self] }
        set { self[FocusedViewModelKey.self] = newValue }
    }
}

@main
struct ATILApp: App {
    @State private var viewModel = ProcessListViewModel()
    @FocusedValue(\.viewModel) private var focusedViewModel

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(viewModel)
                .frame(minWidth: 700, minHeight: 400)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            // Remove default "New Window" command
            CommandGroup(replacing: .newItem) {}

            // Edit menu additions
            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Select All Visible") {
                    focusedViewModel?.selectAllVisible()
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(focusedViewModel == nil)

                Button("Deselect All") {
                    focusedViewModel?.clearSelection()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(focusedViewModel == nil)
            }

            // View menu
            CommandMenu("View") {
                Toggle("Group by App", isOn: Binding(
                    get: { focusedViewModel?.showGrouped ?? true },
                    set: { focusedViewModel?.showGrouped = $0 }
                ))
                .keyboardShortcut("g", modifiers: .command)
                .disabled(focusedViewModel == nil)

                Divider()

                ForEach(ProcessCategory.allCases, id: \.self) { category in
                    Toggle(category.displayName, isOn: Binding(
                        get: { focusedViewModel?.expandedCategories.contains(category) ?? false },
                        set: { expanded in
                            if expanded {
                                focusedViewModel?.expandedCategories.insert(category)
                            } else {
                                focusedViewModel?.expandedCategories.remove(category)
                            }
                        }
                    ))
                }

                Divider()

                Button("Refresh") {
                    Task { await focusedViewModel?.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(focusedViewModel == nil)

                Button("Startup Items…") {
                    focusedViewModel?.openStartupItems()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(focusedViewModel == nil)
            }

            // Process menu
            CommandMenu("Process") {
                Button("Kill") {
                    Task { await focusedViewModel?.killAllSelected() }
                }
                .disabled(focusedViewModel?.selectedProcessIDs.isEmpty ?? true)

                Button(focusedViewModel?.isSelectedSuspended == true ? "Resume" : "Suspend") {
                    focusedViewModel?.toggleSuspendResumeForSelection()
                }
                .disabled(focusedViewModel?.selectedProcessIDs.isEmpty ?? true)

                Divider()

                Button("Ignore") {
                    focusedViewModel?.ignoreAllSelected()
                }
                .disabled(focusedViewModel?.selectedProcessIDs.isEmpty ?? true)

                Button("Create Rule…") {
                    focusedViewModel?.createRuleFromSelected()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(focusedViewModel?.selectedProcess == nil)

                Divider()

                Button("Inspect") {
                    if let process = focusedViewModel?.selectedProcess {
                        focusedViewModel?.inspectProcess(process)
                    }
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(focusedViewModel?.selectedProcess == nil)

                Button("Open Startup Items") {
                    if let process = focusedViewModel?.selectedProcess {
                        focusedViewModel?.openStartupItems(for: process)
                    } else {
                        focusedViewModel?.openStartupItems()
                    }
                }
                .disabled(focusedViewModel == nil)
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Link("ATIL Help", destination: URL(string: "https://github.com")!)
                Link("Report an Issue", destination: URL(string: "https://github.com")!)
            }
        }
    }
}
