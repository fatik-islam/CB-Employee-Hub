import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 8)
                Text(L10n.text(value))
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(CBTheme.text)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.72)
            }

            Text(L10n.text(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CBTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(18)
        .cbGlass(cornerRadius: 22, tint: color.opacity(0.05))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status.lowercased() {
        case "active", "present", "approved", "healthy", "success", "enrolled":
            CBTheme.success
        case "inactive", "absent", "rejected", "critical", "failed":
            CBTheme.danger
        case "leave", "pending", "attention":
            CBTheme.warning
        default:
            CBTheme.muted
        }
    }

    var body: some View {
        Text(L10n.text(status.sentenceCased))
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(status)")
    }
}

struct InitialsAvatar: View {
    let name: String

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(
                LinearGradient(
                    colors: [CBTheme.navy800, CBTheme.navy900],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

struct CreamPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [CBTheme.pageTop, CBTheme.pageBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            content
        }
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.16).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView().controlSize(.large).tint(CBTheme.orange)
                Text("Please wait…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CBTheme.muted)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .cbGlass(cornerRadius: 20, tint: CBTheme.surface.opacity(0.18))
        }
        .transition(.opacity)
    }
}

struct LoadingStateCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(CBTheme.orange)
                .frame(width: 44, height: 44)
                .background(CBTheme.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title))
                    .font(.headline)
                    .foregroundStyle(CBTheme.text)
                Text(L10n.text(message))
                    .font(.subheadline)
                    .foregroundStyle(CBTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cbGlass(cornerRadius: 22, tint: CBTheme.orange.opacity(0.045))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

struct InfoRow: View {
    let symbol: String
    let title: String
    let value: String
    var color: Color = CBTheme.info

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title)).font(.caption.weight(.semibold)).foregroundStyle(CBTheme.muted)
                Text(L10n.text(value)).font(.subheadline.weight(.medium)).foregroundStyle(CBTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
