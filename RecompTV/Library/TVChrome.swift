import SwiftUI
import RecompSources

/// Nativecade's colors, from its logo (docs/branding): an ink-tinted graphite page, coral as the one
/// accent, and mint only for the play triangle that marks what plays now. Text uses the system's
/// primary, secondary and tertiary styles, which are neutral on this page.
enum Palette {
    /// The page behind every screen.
    static let page = Color(red: 0.043, green: 0.051, blue: 0.078)
    /// A raised surface, such as a game without cover art.
    static let raised = Color(red: 0.102, green: 0.118, blue: 0.157)
    /// The logo's N: the current step and the one figure that matters.
    static let coral = Color(red: 1.0, green: 0.443, blue: 0.357)
    /// The logo's play triangle.
    static let mint = Color(red: 0.506, green: 0.890, blue: 0.769)
    /// Errors, toned to sit on the page.
    static let negative = Color(red: 0.898, green: 0.282, blue: 0.302)
}

/// The page every screen sits on.
struct PageBackground: View {
    var body: some View { Palette.page.ignoresSafeArea() }
}

/// The logo's mint play triangle, Nativecade's one status mark: it means "plays now".
struct PlaysNowMark: View {
    var body: some View {
        Image(systemName: "play.fill").foregroundStyle(Palette.mint).accessibilityLabel("Plays now")
    }
}

/// Which platforms Nativecade plays today, and that more arrive with updates. It's built from the
/// supported-platform list, so it updates itself when support grows.
struct SupportRibbon: View {
    var body: some View {
        let platforms = SupportedPlatform.allCases.map(\.title)
        HStack(spacing: 12) {
            PlaysNowMark()
            Text("\(platforms.formatted(.list(type: .and))) \(platforms.count == 1 ? "plays" : "play") now")
            Text("·").foregroundStyle(.tertiary)
            Text("More consoles and games arrive with updates").foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
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

/// Where guided setup is: each step's name over a short bar, coral under the current one.
/// SMB setups have no platform step.
struct SetupSteps: View {
    let current: SetupStage
    var skipsPlatforms = false

    var body: some View {
        let stages = SetupStage.allCases.filter { !skipsPlatforms || $0 != .platforms }
        HStack(alignment: .top, spacing: 32) {
            ForEach(stages, id: \.self) { stage in
                let done = stage.rawValue < current.rawValue
                VStack(alignment: .leading, spacing: 8) {
                    Text(stage.title)
                        .fontWeight(stage == current ? .medium : .regular)
                        .foregroundStyle(stage == current ? AnyShapeStyle(.primary) : done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    Capsule()
                        .fill(stage == current ? AnyShapeStyle(Palette.coral) : AnyShapeStyle(.primary.opacity(done ? 0.24 : 0.08)))
                        .frame(width: 120, height: 4)
                }
            }
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \((stages.firstIndex(of: current) ?? 0) + 1) of \(stages.count): \(current.title)")
    }
}

/// A Nintendo 64 cartridge drawn in code: grey plastic with grip ridges and a printed label carrying
/// the platform's name and count, under a coral band from the logo.
struct Cartridge: View {
    let title: String
    let detail: String?

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(white: 0.43), Color(white: 0.33)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 2))
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(.black.opacity(0.2)).frame(height: 4) }
            }
            .padding(.horizontal, 64).padding(.top, 20)
            VStack(alignment: .leading, spacing: 0) {
                Palette.coral.frame(height: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).fontWeight(.medium)
                    if let detail { Text(detail).font(.caption) }
                }
                .foregroundStyle(Color(red: 0.067, green: 0.110, blue: 0.173))
                .padding(16)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.965, green: 0.953, blue: 0.925))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(EdgeInsets(top: 64, leading: 32, bottom: 32, trailing: 32))
        }
        // A real cartridge's face, about 1.55 to 1.
        .frame(width: 400, height: 260)
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }
}
