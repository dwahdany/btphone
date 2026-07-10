import SwiftUI

@main
struct BTPhoneApp: App {
    @StateObject private var intercom = IntercomController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(intercom)
                .onAppear {
                    // The phone rides in a pocket or mount; never auto-lock.
                    UIApplication.shared.isIdleTimerDisabled = true
                    intercom.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        UIApplication.shared.isIdleTimerDisabled = true
                        intercom.nudgeLinkIfDisconnected()
                    }
                }
        }
    }
}
