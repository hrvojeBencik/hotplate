import SwiftUI

/// Visual tokens. Flutter blue is spent in two places only: the Run button and the status pill.
enum Theme {
    static let accent = Color(red: 0.05, green: 0.52, blue: 0.85)        // #0D85D9
    static let accentBright = Color(red: 0.07, green: 0.73, blue: 0.99)  // #13B9FD
    static let runGradient = LinearGradient(colors: [accent, accentBright], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let logCanvas = Color(red: 0.059, green: 0.078, blue: 0.098)  // #0F1419
    static let logText = Color(red: 0.84, green: 0.87, blue: 0.91)
    static let logMuted = Color(red: 0.52, green: 0.57, blue: 0.63)

    static let success = Color(red: 0.30, green: 0.82, blue: 0.50)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.28)
    static let error = Color(red: 1.00, green: 0.38, blue: 0.38)
    static let info = Color(red: 0.45, green: 0.72, blue: 1.00)

    static func color(for state: SessionState) -> Color {
        switch state {
        case .idle: return .secondary
        case .starting, .stopping: return accentBright
        case .running: return success
        case .reloading, .restarting: return warning
        case .failed: return error
        }
    }

    static func color(for kind: LogKind) -> Color {
        switch kind {
        case .normal: return logText
        case .error: return error
        case .warning: return warning
        case .info: return logMuted
        case .success: return success
        }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

extension View {
    /// A raised control surface: Liquid Glass on macOS 26+, material with a hairline elsewhere.
    @ViewBuilder func cardSurface(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.primary.opacity(0.10)))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.primary.opacity(0.10)))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        }
    }
}

/// Filled capsule button with the Flutter gradient (Run) or a flat tint (Stop).
struct ProminentCapsuleStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background {
                if let tint { Capsule().fill(tint) } else { Capsule().fill(Theme.runGradient) }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .shadow(color: (tint ?? Theme.accent).opacity(configuration.isPressed ? 0.1 : 0.35), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet capsule button for secondary actions (reload, restart).
struct QuietCapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.18 : 0.10)))
            .overlay(Capsule().strokeBorder(.primary.opacity(0.18)))
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// The status pill: colored dot (pulsing while busy) and a short label.
struct StatusPill: View {
    let state: SessionState
    let text: String

    private var busy: Bool {
        switch state { case .starting, .stopping, .reloading, .restarting: return true; default: return false }
    }

    var body: some View {
        let color = Theme.color(for: state)
        HStack(spacing: 7) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.8), radius: busy ? 5 : 3)
                .symbolEffect(.pulse, options: .repeating, isActive: busy)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
        .animation(.easeInOut(duration: 0.25), value: state)
    }
}
