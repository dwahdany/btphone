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
