import AVFoundation
import Combine
import SwiftUI
import os

/// Glues the audio pipeline to the network link and exposes UI state.
@MainActor
final class IntercomController: ObservableObject {
    @Published private(set) var linkState: PeerLink.LinkState = .stopped
    @Published private(set) var stats = PeerLink.Stats()
    @Published private(set) var bufferMilliseconds = 0
    @Published private(set) var micPermissionDenied = false
    @Published private(set) var lastError: String?
    @Published private(set) var linkHint: String?
    /// False whenever the audio engine is not actually producing/consuming
    /// audio — the UI must never claim LIVE while this is false.
    @Published private(set) var audioActive = false

    @Published var isMuted = false {
        didSet {
            audio.isMicMuted = isMuted
            muted = isMuted
        }
    }

    var localDisplayName: String { link.localDisplayName }

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
        link.restart()
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

        // muteTick lives in this closure and is only touched on the audio
        // capture queue. While muted we send an empty keepalive datagram
        // every 25 frames (2/s) so the peer can tell "muted" from "gone".
        var muteTick = 0
        audio.onCapturedFrame = { [weak self] frame in
            guard let self else { return }
            if self.muted {
                muteTick += 1
                if muteTick >= 25 {
                    muteTick = 0
                    self.link.send(frame: Data())
                }
            } else {
                muteTick = 0
                self.link.send(frame: frame)
            }
        }
        link.onPayload = { [weak self] payload in
            self?.audio.enqueuePlayback(payload)
        }
        link.onState = { [weak self] state in
            self?.linkState = state
        }
        link.onHint = { [weak self] hint in
            self?.linkHint = hint
        }
        link.onStats = { [weak self] stats in
            guard let self else { return }
            self.stats = stats
            self.bufferMilliseconds = self.audio.jitter.bufferedMilliseconds
        }

        installAudioObservers()
        installWatchdog()
        startAudio()
        link.start()
    }

    private func startAudio() {
        suppressTriggersUntil = Date().addingTimeInterval(1.5)
        do {
            try audio.start()
            lastError = nil
        } catch {
            lastError = "Audio failed to start: \(error.localizedDescription)"
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
