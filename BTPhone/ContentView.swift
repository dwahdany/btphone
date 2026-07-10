import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var intercom: IntercomController

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
                Spacer()
                muteButton
                Spacer()
                statsFooter
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("BTPhone")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("This phone: \(intercom.localDisplayName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                    Text("No audio coming in — check the other phone")
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
            if !intercom.audioActive && !intercom.micPermissionDenied {
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
            }
            Button {
                intercom.restartLink()
            } label: {
                Label("Restart connection", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.medium))
            }
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    // Oversized target so it works with motorcycle gloves.
    private var muteButton: some View {
        Button {
            intercom.isMuted.toggle()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: intercom.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 64, weight: .bold))
                Text(muteButtonLabel)
                    .font(.headline.weight(.heavy))
                    .tracking(2)
            }
            .foregroundStyle(.white)
            .frame(width: 220, height: 220)
            .background(Circle().fill(muteButtonStyle))
            .shadow(color: muteButtonShadow.opacity(0.4), radius: 24)
        }
        .buttonStyle(.plain)
    }

    private var muteButtonLabel: String {
        if intercom.isMuted { return "MUTED" }
        return intercom.audioActive ? "LIVE" : "AUDIO OFF"
    }

    private var muteButtonStyle: AnyShapeStyle {
        if intercom.isMuted { return AnyShapeStyle(Color.red.gradient) }
        return intercom.audioActive
            ? AnyShapeStyle(Color.green.gradient)
            : AnyShapeStyle(Color.gray.gradient)
    }

    private var muteButtonShadow: Color {
        if intercom.isMuted { return .red }
        return intercom.audioActive ? .green : .gray
    }

    private var statsFooter: some View {
        HStack(spacing: 18) {
            statItem(
                label: "loss",
                value: String(format: "%.1f%%", intercom.stats.recentLossPercent)
            )
            statItem(label: "buffer", value: "\(intercom.bufferMilliseconds) ms")
            statItem(label: "packets", value: "\(intercom.stats.packetsReceived)")
        }
        .frame(maxWidth: .infinity)
    }

    private func statItem(label: String, value: String) -> some View {
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
        case .stopped: return .gray
        case .searching: return .orange
        case .connecting: return .yellow
        case .connected:
            return (intercom.stats.receivingAudio || intercom.stats.peerMuted) ? .green : .yellow
        }
    }

    private var statusText: String {
        switch intercom.linkState {
        case .stopped:
            return "Stopped"
        case .searching:
            return intercom.stats.receivingAudio
                ? "Receiving audio — reconnecting…"
                : "Searching for the other phone…"
        case .connecting(let peer):
            return "Connecting to \(peer)…"
        case .connected(let peer):
            return "Connected to \(peer)"
        }
    }
}
