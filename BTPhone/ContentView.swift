import DeviceDiscoveryUI
import Network
import SwiftUI
import UIKit
import WiFiAware

struct ContentView: View {
    @EnvironmentObject private var intercom: IntercomController
    @EnvironmentObject private var store: EntitlementStore
    private enum PaywallTrigger: String, Identifiable {
        case manual, limit
        var id: String { rawValue }
    }

    @State private var paywallTrigger: PaywallTrigger?
    @State private var showPairingTools = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.12), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                statusCard
                if showPairingCard {
                    pairingCard
                }
                Spacer()
                bigButton
                Spacer()
                statsFooter
                if intercom.sessionActive, let ends = intercom.freeSessionEndsAt {
                    freeSessionRow(ends: ends)
                } else if !intercom.sessionActive, store.gate == .locked {
                    Button("Unlock unlimited sessions") { paywallTrigger = .manual }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if intercom.sessionActive {
                    endButton
                }
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        // One sheet for both entry points: two isPresented sheets would
        // queue back-to-back paywalls when the limit fires while the manual
        // sheet is already open.
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(sessionEnded: trigger == .limit)
        }
        .onChange(of: intercom.sessionLimitReached) { _, reached in
            if reached {
                paywallTrigger = .limit
                intercom.sessionLimitReached = false
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(verbatim: "TwoUp")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            (intercom.isPaired ? Text("Paired") : Text("Not paired yet"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func freeSessionRow(ends: Date) -> some View {
        HStack(spacing: 6) {
            Text("Free session")
            Text(timerInterval: Date.now...max(Date.now, ends), countsDown: true)
                .monospacedDigit()
            Button("Unlock") { paywallTrigger = .manual }
                .font(.footnote.weight(.semibold))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var statusCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            if case .connected = intercom.linkState, !intercom.stats.receivingAudio {
                if intercom.stats.peerMuted {
                    Text("The other phone is muted")
                        .font(.footnote)
                        .foregroundStyle(.cyan)
                } else {
                    // Also shows while the peer's audio is paused by a phone
                    // call or Siri — hence the soft wording.
                    Text("No audio from the other phone — maybe a call or Siri")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            if let hint = intercom.linkHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            if intercom.sessionActive && !intercom.audioActive && !intercom.micPermissionDenied {
                HStack(spacing: 8) {
                    Text("Audio is stopped")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Restart audio") {
                        intercom.restartAudio()
                    }
                    .font(.footnote.weight(.semibold))
                    .tint(.red)
                }
            }
            if let error = intercom.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if intercom.micPermissionDenied {
                Text("Microphone access is required. Enable it in Settings → Privacy → Microphone.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            Button {
                intercom.restartLink()
            } label: {
                Label("Restart connection", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.medium))
            }
            .tint(.secondary)
            // New passenger, new phone: the pairing UI must stay reachable
            // after the first pairing (iOS offers no in-app unpair).
            if intercom.isPaired {
                Button {
                    showPairingTools.toggle()
                } label: {
                    (showPairingTools ? Text("Hide pairing") : Text("Pair a different phone"))
                        .font(.footnote.weight(.medium))
                }
                .tint(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Pairing

    private var showPairingCard: Bool {
        if showPairingTools { return true }
        if !intercom.isPaired { return true }
        if case .unpaired = intercom.linkState { return true }
        return false
    }

    /// One phone taps "Be discoverable", the other taps "Find other phone".
    private var pairingCard: some View {
        VStack(spacing: 14) {
            Text("Pair the two phones once")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("On one phone tap Be discoverable, on the other tap Find other phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if intercom.isPaired {
                Text("Pairing a new phone doesn't remove old ones — manage pairings in iOS Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if IntercomController.demoScene != nil {
                // Screenshot rig: the real discovery views would crash the
                // entitlement-less Simulator build.
                HStack(spacing: 12) {
                    pairingButtonLabel("dot.radiowaves.left.and.right", "Be discoverable")
                    pairingButtonLabel("magnifyingglass", "Find other phone")
                }
            } else {
                pairingButtons
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private var pairingButtons: some View {
            HStack(spacing: 12) {
                if let publishable = WAPublishableService.allServices[PeerLink.serviceName] {
                    DevicePairingView(
                        WAPublisherListener.wifiAware(
                            .connecting(to: publishable, from: .userSpecifiedDevices, datapath: .realtime)
                        )
                    ) {
                        pairingButtonLabel("dot.radiowaves.left.and.right", "Be discoverable")
                    } fallback: {
                        pairingUnavailableLabel
                    }
                }
                if let subscribable = WASubscribableService.allServices[PeerLink.serviceName] {
                    DevicePicker(
                        WASubscriberBrowser.wifiAware(
                            .connecting(to: .userSpecifiedDevices, from: subscribable)
                        ),
                        onSelect: { _ in
                            // Pairing done; PeerLink's paired-device monitor
                            // picks it up and connects automatically.
                        },
                        label: {
                            pairingButtonLabel("magnifyingglass", "Find other phone")
                        },
                        fallback: {
                            pairingUnavailableLabel
                        }
                    )
                }
            }
    }

    private func pairingButtonLabel(_ icon: String, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.blue.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var pairingUnavailableLabel: some View {
        Text("Wi-Fi Aware unavailable")
            .font(.footnote)
            .foregroundStyle(.red)
    }

    // MARK: - Big button (start / mute)

    // Oversized target so it works with motorcycle gloves. When the session
    // is stopped it starts the intercom; while running it toggles mute —
    // ending the session is deliberately a separate, smaller button.
    private var bigButton: some View {
        Button {
            if intercom.sessionActive {
                intercom.isMuted.toggle()
            } else {
                intercom.startIntercom()
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: bigButtonIcon)
                    .font(.system(size: 64, weight: .bold))
                Text(bigButtonLabel)
                    .font(.headline.weight(.heavy))
                    .tracking(2)
            }
            .foregroundStyle(.white)
            .frame(width: 220, height: 220)
            .background(Circle().fill(bigButtonStyle))
            .shadow(color: bigButtonShadow.opacity(0.4), radius: 24)
        }
        .buttonStyle(.plain)
    }

    private var endButton: some View {
        Button {
            intercom.stopIntercom()
        } label: {
            Label("End intercom", systemImage: "power")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var bigButtonIcon: String {
        if !intercom.sessionActive { return "power" }
        return intercom.isMuted ? "mic.slash.fill" : "mic.fill"
    }

    private var bigButtonLabel: String {
        if !intercom.sessionActive { return String(localized: "START") }
        if intercom.isMuted { return String(localized: "MUTED") }
        return intercom.audioActive
            ? String(localized: "LIVE")
            : String(localized: "AUDIO OFF")
    }

    private var bigButtonStyle: AnyShapeStyle {
        if !intercom.sessionActive { return AnyShapeStyle(Color.blue.gradient) }
        if intercom.isMuted { return AnyShapeStyle(Color.red.gradient) }
        return intercom.audioActive
            ? AnyShapeStyle(Color.green.gradient)
            : AnyShapeStyle(Color.gray.gradient)
    }

    private var bigButtonShadow: Color {
        if !intercom.sessionActive { return .blue }
        if intercom.isMuted { return .red }
        return intercom.audioActive ? .green : .gray
    }

    // MARK: - Stats

    private var statsFooter: some View {
        HStack(spacing: 18) {
            statItem(
                label: "loss",
                value: String(
                    format: "%.1f%%", locale: .current,
                    intercom.stats.recentLossPercent
                )
            )
            statItem(label: "buffer", value: "\(intercom.bufferMilliseconds) ms")
            statItem(label: "packets", value: "\(intercom.stats.packetsReceived)")
        }
        .frame(maxWidth: .infinity)
    }

    private func statItem(label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch intercom.linkState {
        case .stopped, .unsupported: return .gray
        case .unpaired: return .blue
        case .searching: return .orange
        case .connecting: return .yellow
        case .connected:
            return (intercom.stats.receivingAudio || intercom.stats.peerMuted) ? .green : .yellow
        }
    }

    private var statusText: String {
        switch intercom.linkState {
        case .stopped:
            return String(localized: "Not running — tap START")
        case .unsupported:
            return String(localized: "This iPhone doesn't support Wi-Fi Aware")
        case .unpaired:
            return String(localized: "Pair with the other phone to start")
        case .searching:
            return intercom.stats.receivingAudio
                ? String(localized: "Receiving audio — reconnecting…")
                : String(localized: "Searching for the other phone…")
        case .connecting(let peer):
            return String(localized: "Connecting to \(peer)…")
        case .connected(let peer):
            return String(localized: "Connected to \(peer)")
        }
    }
}
