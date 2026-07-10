import AVFoundation
import Combine
import SwiftUI
import os

/// Glues the audio pipeline to the network link and exposes UI state.
@MainActor
final class IntercomController: ObservableObject {
    private static let log = Logger(subsystem: "com.wahdany.btphone", category: "Audio")
    @Published private(set) var linkState: PeerLink.LinkState = .stopped
    @Published private(set) var stats = PeerLink.Stats()
    @Published private(set) var bufferMilliseconds = 0
    @Published private(set) var micPermissionDenied = false
    @Published private(set) var lastError: String?
    @Published private(set) var linkHint: String?
    @Published private(set) var isPaired = false
    /// False whenever the audio engine is not actually producing/consuming
    /// audio — the UI must never claim LIVE while this is false.
    @Published private(set) var audioActive = false

    @Published var isMuted = false {
        didSet {
            audio.isMicMuted = isMuted
            muted = isMuted
        }
    }

    private let audio = IntercomAudio()
    private let link = PeerLink()
    // Mirror of isMuted readable from the audio capture queue.
    private let mutedFlag = OSAllocatedUnfairLock(initialState: false)
    private var muted: Bool {
        get { mutedFlag.withLock { $0 } }
        set { mutedFlag.withLock { $0 = newValue } }
    }

    private var restartWork: DispatchWorkItem?
    private var watchdog: Timer?
    private var observers: [NSObjectProtocol] = []
    private var startedOnce = false
    private var pipelinesStarted = false
    /// Set while another app (phone call, Siri) holds the audio session.
    private var interruptedAt: Date?
    /// Starting the engine posts route/config-change notifications of its
    /// own; ignore triggers until this deadline so a restart can't feed
    /// itself. The watchdog catches anything genuinely missed.
    private var suppressTriggersUntil = Date.distantPast

    func start() {
        guard !startedOnce else { return }
        startedOnce = true

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.startPipelines()
                } else {
                    self.micPermissionDenied = true
                }
            }
        }
    }

    func restartLink() {
        let link = link
        Task { await link.restart() }
    }

    /// Called when the app returns to the foreground: if the link is limping
    /// (a stale attempt from before backgrounding), rebuild it right away so
    /// "look at the phone" doubles as the recovery gesture.
    func nudgeLinkIfDisconnected() {
        guard pipelinesStarted else { return }
        switch linkState {
        case .searching, .connecting:
            restartLink()
        default:
            break
        }
    }

    func restartAudio() {
        restartWork?.cancel()
        restartWork = nil
        audio.stop()
        startAudio()
    }

    private func startPipelines() {
        guard !pipelinesStarted else { return }
        pipelinesStarted = true

        let link = self.link
        let audio = self.audio

        // muteTick lives in this closure and is only touched on the audio
        // capture queue. While muted we send an empty keepalive datagram
        // every 25 frames (2/s) so the peer can tell "muted" from "gone".
        var muteTick = 0
        let mutedFlag = self.mutedFlag
        audio.onCapturedFrame = { frame in
            if mutedFlag.withLock({ $0 }) {
                muteTick += 1
                if muteTick >= 25 {
                    muteTick = 0
                    link.send(frame: Data())
                }
            } else {
                muteTick = 0
                link.send(frame: frame)
            }
        }

        Task {
            await link.configure(
                onPayload: { [weak audio] payload in
                    audio?.enqueuePlayback(payload)
                },
                onState: { [weak self] state in
                    MainActor.assumeIsolated { self?.linkState = state }
                },
                onStats: { [weak self] stats in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.stats = stats
                        self.bufferMilliseconds = self.audio.jitter.bufferedMilliseconds
                    }
                },
                onHint: { [weak self] hint in
                    MainActor.assumeIsolated { self?.linkHint = hint }
                },
                onPairedChanged: { [weak self] paired in
                    MainActor.assumeIsolated { self?.isPaired = paired }
                }
            )
            await link.start()
        }

        installAudioObservers()
        installWatchdog()
        startAudio()
    }

    private func startAudio() {
        suppressTriggersUntil = Date().addingTimeInterval(1.5)
        do {
            try audio.start()
            lastError = nil
            Self.log.info("audio started, engineRunning=\(self.audio.engineRunning)")
        } catch {
            lastError = "Audio failed to start: \(error.localizedDescription)"
            Self.log.error("audio start failed: \(error, privacy: .public)")
        }
        audioActive = audio.isRunning && audio.engineRunning
        if audioActive {
            // A successful session activation proves the interruption is
            // over even if iOS never delivered .ended; re-arm the
            // route/config-change observers.
            interruptedAt = nil
        }
    }

    /// Debounced full audio restart; used when the route (helmet headset) or
    /// engine configuration changes underneath us.
    private func scheduleAudioRestart(after delay: TimeInterval = 0.5) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWork = nil
            self.audio.stop()
            self.startAudio()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Last line of defense: whatever notification was missed or restart
    /// failed, if audio should be running and isn't, bring it back.
    private func installWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdogTick() }
        }
    }

    private func watchdogTick() {
        guard pipelinesStarted else { return }
        audioActive = audio.isRunning && audio.engineRunning
        if let interruptedAt {
            // Give the interrupting audio (a phone call) 15 s of grace; if
            // no .ended ever arrives, start probing — session activation
            // simply fails until the other app lets go, then we recover.
            guard Date().timeIntervalSince(interruptedAt) > 15 else { return }
        }
        guard !audioActive, restartWork == nil else { return }
        audio.stop()
        startAudio()
    }

    private func installAudioObservers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    self.interruptedAt = Date()
                    self.restartWork?.cancel()
                    self.restartWork = nil
                    self.audio.stop()
                    self.audioActive = false
                case .ended:
                    self.interruptedAt = nil
                    if options.contains(.shouldResume) {
                        self.scheduleAudioRestart(after: 0.1)
                    }
                    // Without .shouldResume the watchdog re-probes shortly.
                @unknown default:
                    break
                }
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
            MainActor.assumeIsolated {
                guard let self, self.interruptedAt == nil,
                      Date() >= self.suppressTriggersUntil else { return }
                switch reason {
                case .newDeviceAvailable, .oldDeviceUnavailable, .override, .routeConfigurationChange:
                    self.scheduleAudioRestart()
                default:
                    break
                }
            }
        })

        // The engine stops itself on configuration changes (sample rate or
        // channel count shifts when a headset attaches); bring it back up.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The engine already stopped itself; reflect that in the UI
                // right away even if the restart below is suppressed (the
                // watchdog heals it within 2 s).
                self.audioActive = self.audio.isRunning && self.audio.engineRunning
                guard self.audio.isRunning, self.interruptedAt == nil,
                      Date() >= self.suppressTriggersUntil else { return }
                self.scheduleAudioRestart()
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleAudioRestart()
            }
        })
    }
}
