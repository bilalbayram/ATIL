import SwiftUI

struct ProcessIconView: View {
    let process: ATILProcess

    var body: some View {
        if let icon = process.appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "gearshape.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}
