import SwiftUI
import TodoshiCore

// MARK: - Surfaces

struct TodoshiSurface: ViewModifier {
    var cornerRadius: CGFloat = TodoshiRadius.card
    var elevated: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(TodoshiBrand.cardBackground)
                    .shadow(
                        color: elevated && colorScheme == .light ? TodoshiBrand.cardShadow : .clear,
                        radius: 14,
                        x: 0,
                        y: 6
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(TodoshiBrand.cardStroke, lineWidth: 0.5)
            }
    }
}

extension View {
    func todoshiSurface(cornerRadius: CGFloat = TodoshiRadius.card) -> some View {
        modifier(TodoshiSurface(cornerRadius: cornerRadius))
    }
}

struct TodoshiCard<Content: View>: View {
    var padding: CGFloat = TodoshiSpacing.sm
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .todoshiSurface()
    }
}

// MARK: - Section header

struct TodoshiSectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: TodoshiSpacing.xs) {
            Text(title)
                .font(TodoshiTypography.section)
                .foregroundStyle(.primary)
            if let count {
                Text("\(count)")
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Buttons

struct TodoshiPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: TodoshiIconSize.hit)
            .background(TodoshiBrand.accent.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
    }
}

struct TodoshiSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(TodoshiBrand.accent)
            .frame(maxWidth: .infinity, minHeight: TodoshiIconSize.hit)
            .background(
                (configuration.isPressed ? TodoshiBrand.accentSoft : TodoshiBrand.accentMuted),
                in: Capsule()
            )
    }
}

struct TodoshiIconButton: View {
    let systemName: String
    var size: CGFloat = TodoshiIconSize.hit
    var style: Style = .plain
    let action: () -> Void

    enum Style {
        case plain
        case tinted
        case filled
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background { background }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .plain: return TodoshiBrand.accent
        case .tinted: return TodoshiBrand.accent
        case .filled: return .white
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .plain:
            Color.clear
        case .tinted:
            Circle().fill(TodoshiBrand.accentMuted)
        case .filled:
            Circle().fill(TodoshiBrand.accent)
        }
    }
}

// MARK: - Avatar

struct TodoshiAvatar: View {
    let displayName: String?
    var size: CGFloat = 40
    var isLoading: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(TodoshiBrand.accentMuted)
                .frame(width: size, height: size)

            let initials = ProfileAvatarInitialsPolicy.initials(from: displayName)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(TodoshiBrand.accent.opacity(0.7))
            } else {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(TodoshiBrand.accent)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            if isLoading {
                ProgressView()
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Status badge

struct TodoshiStatusBadge: View {
    let status: TaskStatus
    var projectType: ProjectType = .tasks

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(TodoshiStatusColor.indicator(for: status))
                .frame(width: 7, height: 7)
            Text(ProjectStatusPolicy.displayName(status, for: projectType))
                .font(TodoshiTypography.metadata.weight(.medium))
        }
        .foregroundStyle(TodoshiStatusColor.indicator(for: status))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(TodoshiStatusColor.indicator(for: status).opacity(0.12), in: Capsule())
        .accessibilityLabel(ProjectStatusPolicy.displayName(status, for: projectType))
    }
}

// MARK: - Empty state

struct TodoshiEmptyState: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: TodoshiSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(TodoshiBrand.accent.opacity(0.55))
            Text(title)
                .font(TodoshiTypography.title)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(TodoshiTypography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(TodoshiPrimaryButtonStyle())
                    .frame(maxWidth: 240)
            }
        }
        .padding(TodoshiSpacing.lg)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact add action

/// Single branded add affordance — circular + with contextual label.
struct TodoshiCompactAddAction: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TodoshiBrand.accent)
                    .frame(width: 22, height: 22)
                    .background(TodoshiBrand.accentMuted, in: Circle())
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TodoshiBrand.accent)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Project type glyph well

struct TodoshiProjectIconWell: View {
    let systemName: String
    let colorHex: String
    var size: CGFloat = 32
    var projectType: ProjectType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(TodoshiBrand.iconWell(for: colorHex))
                .frame(width: size, height: size)

            Image(systemName: resolvedSymbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(TodoshiColor.from(hex: colorHex))
        }
        .accessibilityHidden(true)
    }

    private var resolvedSymbol: String {
        projectType == .checklist ? "checklist" : systemName
    }
}

// MARK: - Tab bar

/// Floating bottom bar: four destinations around a raised add button.
struct TodoshiTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    /// Space content reserves under itself so nothing scrolls behind the bar.
    static let reservedHeight: CGFloat = 76

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            item(.dashboard)
            item(.projects)
            addButton
            item(.calendar)
            item(.search)
        }
        .padding(.horizontal, TodoshiSpacing.xs)
        .frame(height: 64)
        .background {
            Capsule(style: .continuous)
                .fill(TodoshiBrand.cardBackground)
                .shadow(color: TodoshiBrand.cardShadow, radius: 16, y: 6)
                .overlay(Capsule(style: .continuous).strokeBorder(TodoshiBrand.cardStroke, lineWidth: 0.5))
        }
        .padding(.horizontal, TodoshiSpacing.md)
        .padding(.bottom, TodoshiSpacing.xxs)
        // The bar has a fixed height; larger type would collide. Long-press shows full labels (HUD).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? TodoshiBrand.accent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: TodoshiIconSize.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(TodoshiBrand.accent, in: Circle())
                .shadow(color: TodoshiBrand.accent.opacity(0.35), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .offset(y: -14)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(TodoshiL10n.tr("tab.add"))
    }
}
