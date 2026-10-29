import SwiftUI
import UIKit

@MainActor
private enum NativecadeWindow {
    static var window: UIWindow?

    static func show() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NativecadeLibraryRoot())
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
    }

    static func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}

private struct NativecadeLibraryRoot: View {
    @State private var phase = ScenePhase.active

    var body: some View {
        RecompTVRootView()
            .environment(\.scenePhase, phase)
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in phase = .active }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { _ in phase = .inactive }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification)) { _ in phase = .background }
    }
}

// SDL invokes these C callbacks on UIKit's main thread after its scene activates.
@_cdecl("NativecadePresentLibrary")
func nativecadePresentLibrary() { MainActor.assumeIsolated { NativecadeWindow.show() } }

@_cdecl("NativecadeHideLibrary")
func nativecadeHideLibrary() { MainActor.assumeIsolated { NativecadeWindow.hide() } }
