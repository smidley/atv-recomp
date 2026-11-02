import SwiftUI
import RecompSources

/// Which platforms Nativecade plays today, and that more arrive with updates. It's built from
/// the supported-platform list, so it updates itself when support grows.
struct SupportRibbon: View {
    var body: some View {
        HStack(spacing: 18) {
            Text("Supported now").bold()
                .foregroundStyle(Color(red: 0.02, green: 0.15, blue: 0.06))
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(Color(red: 0.2, green: 0.78, blue: 0.35), in: Capsule())
            Text(SupportedPlatform.allCases.map(\.title).formatted(.list(type: .and)))
            Text("Coming over time")
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(.white.opacity(0.14), in: Capsule())
            Text("more consoles and games, added with each update")
        }
        .font(.caption)
        .opacity(0.85)
        .accessibilityElement(children: .combine)
    }
}

/// The backdrop before any cover art exists: violet and cyan glows on near-black.
struct CalmBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.051, blue: 0.071)
            RadialGradient(colors: [Color(red: 0.49, green: 0.3, blue: 1).opacity(0.4), .clear],
                           center: UnitPoint(x: 0.2, y: 0.3), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Color(red: 0, green: 0.75, blue: 1).opacity(0.3), .clear],
                           center: UnitPoint(x: 0.85, y: 0.8), startRadius: 0, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

enum SetupStage: Int, CaseIterable {
    case connect, platforms, games

    var title: String {
        switch self {
        case .connect: "Connect"
        case .platforms: "Platforms"
        case .games: "Games"
        }
    }
}

/// Where guided setup is: earlier steps show a check. SMB setups have no platform step.
struct StepPills: View {
    let current: SetupStage
    var skipsPlatforms = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(SetupStage.allCases.filter { !skipsPlatforms || $0 != .platforms }, id: \.self) { stage in
                let done = stage.rawValue < current.rawValue
                HStack(spacing: 8) {
                    if done { Image(systemName: "checkmark").foregroundStyle(.green) }
                    Text(stage.title)
                }
                .font(.caption.weight(stage == current ? .bold : .regular))
                .foregroundStyle(stage == current ? .black : .white)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(stage == current ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
                .opacity(stage == current || done ? 1 : 0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + (skipsPlatforms && current == .games ? 0 : 1)) of \(skipsPlatforms ? 2 : 3): \(current.title)")
    }
}

/// The small uppercase line above a screen's title.
struct Kicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption).tracking(4).foregroundStyle(.secondary)
    }
}
