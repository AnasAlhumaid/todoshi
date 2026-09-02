import SwiftUI

struct PlaceholderTabView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
                .multilineTextAlignment(.center)
        }
        .padding(NexusSpacing.md)
    }
}
