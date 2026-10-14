import SwiftUI
import TodoshiCore

/// Lightweight non-modal toast for brief feedback (permission denied, etc.).
struct TodoshiToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .padding(.horizontal, TodoshiSpacing.md)
            .padding(.vertical, TodoshiSpacing.sm)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TodoshiRadius.md, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(message)
    }
}

extension View {
    /// Presents `message` as a bottom toast that auto-dismisses. Binding clears when dismissed.
    func todoshiToast(
        message: Binding<String?>,
        duration: TimeInterval = TodoshiToastPolicy.defaultVisibleDuration
    ) -> some View {
        modifier(TodoshiToastModifier(message: message, duration: duration))
    }
}

private struct TodoshiToastModifier: ViewModifier {
    @Binding var message: String?
    var duration: TimeInterval

    @State private var generation: UInt64 = 0
    @AccessibilityFocusState private var toastFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    TodoshiToastBanner(message: message)
                        .padding(.horizontal, TodoshiSpacing.lg)
                        .padding(.bottom, TodoshiSpacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityFocused($toastFocused)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: message)
            .onChange(of: message) { _, newValue in
                guard newValue != nil else { return }
                generation &+= 1
                let token = generation
                toastFocused = true
                Task { @MainActor in
                    let nanos = UInt64(max(duration, 0.5) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    guard TodoshiToastPolicy.shouldClear(
                        activeGeneration: generation,
                        clearingGeneration: token
                    ) else { return }
                    message = nil
                }
            }
    }
}
