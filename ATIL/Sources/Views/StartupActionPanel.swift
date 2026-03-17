import SwiftUI

struct StartupActionPanel: View {
    @Environment(StartupItemsViewModel.self) private var viewModel

    let group: StartupAppGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    refreshButton
                    blockButton
                    disableButton
                    moreButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        refreshButton
                        blockButton
                    }

                    HStack(spacing: 8) {
                        disableButton
                        moreButton
                    }
                }
            }

            StartupActionStatusLine(
                feedback: viewModel.actionFeedback,
                selectedItemLabel: viewModel.selectedItem?.displayLabel
            )
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .padding()
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refreshManually() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.isPerformingUserAction)
    }

    private var blockButton: some View {
        Button {
            Task {
                if group.isBlocked {
                    await viewModel.unblockSelectedApp()
                } else {
                    await viewModel.blockSelectedApp()
                }
            }
        } label: {
            Label(group.isBlocked ? "Unblock App" : "Block App", systemImage: group.isBlocked ? "shield" : "shield.slash")
        }
        .disabled(viewModel.isPerformingUserAction)
    }

    private var disableButton: some View {
        Button {
            Task { await viewModel.disableSelectedItem() }
        } label: {
            Label("Disable", systemImage: "power.slash")
        }
        .disabled(!canDisableSelectedItem)
    }

    private var moreButton: some View {
        Menu {
            Button("Kill Current Process") {
                Task { await viewModel.killSelectedProcess() }
            }
            .disabled(viewModel.selectedRunningProcess == nil || viewModel.isPerformingUserAction)

            Button("Reveal File") {
                viewModel.revealSelectedItem()
            }
            .disabled(!canRevealSelectedItem || viewModel.isPerformingUserAction)

            Divider()

            Button("Delete Plist File", role: .destructive) {
                viewModel.confirmDeleteSelectedItem()
            }
            .disabled(!canDeleteSelectedPlist || viewModel.isPerformingUserAction)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(viewModel.selectedItem == nil || viewModel.isPerformingUserAction)
    }

    private var canDisableSelectedItem: Bool {
        guard let item = viewModel.selectedItem else { return false }
        return item.canDisable && item.state != .unknown && !viewModel.isPerformingUserAction
    }

    private var canRevealSelectedItem: Bool {
        guard let item = viewModel.selectedItem else { return false }
        return item.plistPath != nil || item.executablePath != nil
    }

    private var canDeleteSelectedPlist: Bool {
        guard let item = viewModel.selectedItem else { return false }
        return item.canDeletePlist
    }
}

struct StartupActionStatusLine: View {
    let feedback: StartupActionFeedback?
    let selectedItemLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            if let feedback {
                switch feedback.style {
                case .progress:
                    ProgressView()
                        .controlSize(.small)
                    Text(feedback.message)
                        .foregroundStyle(.secondary)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(feedback.message)
                        .foregroundStyle(.green)
                }
            } else if let selectedItemLabel {
                Image(systemName: "cursorarrow.click.2")
                    .foregroundStyle(.secondary)
                Text("Selected item: \(selectedItemLabel)")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(.secondary)
                Text("Select a startup item to disable, reveal, or stop it.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(minHeight: 18, alignment: .leading)
    }
}
