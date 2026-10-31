import SwiftUI

@MainActor
struct FoundationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = ProbeSession()
    @FocusState private var focusedControl: Control?
    @State private var gameLog: [String]?

    private enum Control: Hashable {
        case rerun
        case nextColor
        case confirmVisible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("RecompTV").font(.largeTitle.bold())
                Text("Native tvOS foundation check").font(.title3)
                Text(session.environment).font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 12) {
                    MetalProbeView(session: session)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .accessibilityLabel("Metal test surface. Expected color: \(session.colorName)")
                    Text("Expected: a solid \(session.colorName.lowercased()) frame")
                        .font(.headline)
                    Text(session.drawableDescription)
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 20) {
                    Label(
                        session.bridgePassed ? "C++ bridge returned 42" : "C++ bridge check failed",
                        systemImage: session.bridgePassed ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    Text("19 + 23 = \(session.nativeAnswer)").font(.caption)
                    Divider()
                    MetalEvidenceView(evidence: session.evidence, isActive: session.isActive)
                    Divider()
                    Text(session.device?.name ?? "Metal device unavailable").font(.headline)
                    Text("tvOS \(session.systemVersion)").font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 24) {
                HStack(spacing: 24) {
                    Button("Rerun check") { session.rerun() }
                        .focused($focusedControl, equals: .rerun)
                    Button("Next test color") { session.nextColor() }
                        .focused($focusedControl, equals: .nextColor)
                    Button("Confirm \(session.colorName.lowercased()) frame") {
                        session.confirmVisibleFrame()
                    }
                    .focused($focusedControl, equals: .confirmVisible)
                    .disabled(!session.evidence.canConfirmVisibility)
                }
                .disabled(!session.isActive)
                Button("Last game log") { gameLog = GameLogView.load() }
            }

            Text("Foundation probe only. Use Library to connect a server and verify a ROM. Native gameplay is not integrated.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.07))
        .preferredColorScheme(.dark)
        .defaultFocus($focusedControl, .rerun)
        .fullScreenCover(isPresented: Binding(get: { gameLog != nil }, set: { if !$0 { gameLog = nil } })) {
            GameLogView(lines: gameLog ?? [])
        }
        .onAppear { session.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { session.setActive(scenePhase == .active) }
        .onDisappear { session.setActive(false) }
    }
}

private struct MetalEvidenceView: View {
    let evidence: FrameEvidence
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isActive {
                Text("Checks paused while the app is inactive")
            } else {
                switch evidence.status {
                case .waiting:
                    Text("Waiting for GPU completion")
                case .needsVisualConfirmation:
                    Text("GPU completed · confirm the visible color")
                case .passed:
                    Label("Visible frame confirmed by you", systemImage: "checkmark.circle")
                case .failed(let message):
                    Label("Metal check failed", systemImage: "exclamationmark.triangle")
                    Text(message).font(.caption)
                }
                Text("GPU completion: \(evidence.gpuCompleted ? "received" : "pending")")
                Text("Visual check: \(evidence.visuallyConfirmed ? "confirmed" : "not yet confirmed")")
            }
        }
        .font(.callout)
    }
}

/// The last game's console output, which NativecadeRuntime.mm keeps while a game runs, with a
/// backtrace when it crashes. TestFlight builds run without a debugger; this shows a failure on the
/// Apple TV itself. Menu closes it; each line takes focus, so the remote scrolls through them.
private struct GameLogView: View {
    let lines: [String]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index].isEmpty ? " " : lines[index])
                        .font(.system(size: 22, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusable()
                }
            }
            .padding(48)
        }
        .background(Color(white: 0.07))
        .preferredColorScheme(.dark)
    }

    static func load() -> [String] {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nativecade/Logs/last-game.log")
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return ["No game has run since the app was installed."] }
        // The end of the log, where a failure is.
        let text = String(decoding: data.suffix(96 * 1024), as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(600).map(String.init)
    }
}
