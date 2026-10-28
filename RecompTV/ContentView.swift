import SwiftUI

struct ContentView: View {
    @State private var probeResult: Int32?
    @State private var paletteIndex: UInt32 = 0
    @State private var metalStatus = "Waiting for Metal"

    var body: some View {
        HStack(spacing: 64) {
            VStack(alignment: .leading, spacing: 28) {
                Text("RecompTV")
                    .font(.largeTitle.bold())
                Text("Native tvOS proof of concept")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider()

                Label(
                    probeResult.map { "C++ returned \($0)" } ?? "Running C++ probe",
                    systemImage: probeResult == 42 ? "checkmark.circle.fill" : "cpu"
                )
                .accessibilityIdentifier("nativeProbeResult")

                Label(metalStatus, systemImage: "display")
                    .accessibilityIdentifier("metalStatus")
                    .font(.headline)

                Button("Change test color") {
                    paletteIndex = (paletteIndex + 1) % 3
                    metalStatus = "Waiting for Metal"
                }
                .accessibilityIdentifier("changeColor")
                .padding(.top, 12)

                Text("The C++ module supplies the color.\nMetal clears and presents the frame.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Foundation only · No game runtime loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 660, alignment: .leading)

            MetalSurface(paletteIndex: paletteIndex, status: $metalStatus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityLabel("Metal test frame")
        }
        .padding(80)
        .background(Color.black)
        .task {
            probeResult = RTVRunNativeProbe()
            print("RecompTV: C++ probe returned \(probeResult ?? -1)")
        }
    }
}
