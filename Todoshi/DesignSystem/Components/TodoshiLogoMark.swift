import SwiftUI

/// Official Todoshi logo — raster asset shared with App Icon and Launch Screen.
struct TodoshiLogoMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("TodoshiLogo")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Brand wordmark — always "Todoshi", never localized.
struct TodoshiWordmark: View {
    var size: Font = .title2.weight(.bold)

    var body: some View {
        Text("Todoshi")
            .font(size)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}
