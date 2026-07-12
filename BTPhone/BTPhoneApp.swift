import SwiftUI

@main
struct BTPhoneApp: App {
    @StateObject private var intercom = IntercomController()
    @StateObject private var store = EntitlementStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(intercom)
                .environmentObject(store)
                .onAppear {
                    #if DEBUG
                    // Screenshot rig: fake a session state instead of
                    // starting the real pipelines (no mic prompt, works in
                    // the Simulator where Wi-Fi Aware doesn't).
                    if let scene = IntercomController.demoScene {
                        intercom.applyDemoScene(scene)
                        return
                    }
                    #endif
                    store.start()
                    intercom.entitlements = store
                    intercom.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // While a session runs the phone rides in a pocket
                        // or mount; never auto-lock. Off-session, lock away.
                        UIApplication.shared.isIdleTimerDisabled = intercom.sessionActive
                        intercom.nudgeLinkIfDisconnected()
                    }
                }
        }
    }
}
