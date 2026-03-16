import SwiftUI

extension AutoRule.RuleAction {
    var symbolName: String {
        switch self {
        case .kill: "xmark.circle.fill"
        case .suspend: "pause.circle.fill"
        case .markRedundant: "archivebox.circle.fill"
        case .markSuspicious: "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .kill: .red
        case .suspend: .orange
        case .markRedundant: .blue
        case .markSuspicious: .yellow
        }
    }
}
