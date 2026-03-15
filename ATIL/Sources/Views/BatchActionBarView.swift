import SwiftUI

/// Floating batch action bar shown when multiple processes are selected.
struct BatchActionBarView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    let selectedCount: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("\(selectedCount) selected")
                .font(.headline)

            Divider()
                .frame(height: 20)

            Button {
                Task { await viewModel.killAllSelected() }
            } label: {
                Label("Kill All", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityHint("Terminates all selected processes")

            Button {
                viewModel.suspendAllSelected()
            } label: {
                Label("Suspend All", systemImage: "pause.circle")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.ignoreAllSelected()
            } label: {
                Label("Ignore All", systemImage: "eye.slash")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                viewModel.clearSelection()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batch actions for \(selectedCount) selected processes")
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
        .padding(.horizontal, 16)
    }
}
