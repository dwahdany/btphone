import Foundation
import Network
import UIKit

/// Peer discovery and audio transport over peer-to-peer Wi-Fi (AWDL) and,
/// when available, regular local networks.
///
/// Both phones advertise a Bonjour service and browse for it simultaneously.
/// Audio flows over two independent one-way UDP streams: my browser connects
/// to your listener to carry my mic, yours connects to mine to carry your
/// mic. That symmetry removes any need for role negotiation — both phones
/// just launch the app.
///
/// Datagrams with an empty payload are mute keepalives: they keep the flow
/// (and the peer's "link is alive" signal) up while the mic is muted.
final class PeerLink {
    enum LinkState: Equatable {
        case stopped
        case searching
        case connecting(peer: String)
        case connected(peer: String)
    }

    struct Stats {
        var packetsReceived: Int = 0
        var packetsLost: Int = 0
        var lateDrops: Int = 0
        /// Loss over roughly the last 10 seconds — what the UI shows.
        var recentLossPercent: Double = 0
        var receivingAudio: Bool = false
        /// The peer's flow is alive but it is deliberately sending silence.
        var peerMuted: Bool = false
    }

    /// Full advertised name, e.g. "Dariush's iPhone#3f2a". The random suffix
    /// keeps names unique even when both phones report the generic "iPhone".
    let localName: String

    var localDisplayName: String { Self.displayName(from: localName) }

    /// Called on the network queue with the raw audio payload of a datagram.
    var onPayload: ((Data) -> Void)?
    /// Called on the main queue.
    var onState: ((LinkState) -> Void)?
    /// Called on the main queue roughly once per second.
    var onStats: ((Stats) -> Void)?
    /// Called on the main queue with a user-facing diagnostic (or nil to clear).
    var onHint: ((String?) -> Void)?

    private static let serviceType = "_btphone._udp"
    // kDNSServiceErr_PolicyDenied: the user declined the Local Network prompt.
    private static let dnsPolicyDenied: Int32 = -65570

    private let queue = DispatchQueue(label: "btphone.network", qos: .userInteractive)

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var inbound: NWConnection?
    private var outbound: NWConnection?
    private var outboundPeerName: String?
    private var outboundReady = false
    private var started = false

    /// Once the listener binds, keep that port for every later restart so a
    /// peer whose UDP flow is pinned to it keeps reaching us.
    private var boundPort: NWEndpoint.Port?

    private var txSequence: UInt32 = 0
    private var highestRxSequence: UInt32?
    /// Names that recently failed to connect, so evaluate() prefers others.
    private var recentlyFailedPeers: [String: Date] = [:]
    private var stats = Stats()
    private var lastAudioDate: Date?
    private var lastKeepaliveDate: Date?
    private var statsTimer: DispatchSourceTimer?
    // Snapshots of (received, lost) deltas for the windowed loss figure.
    private var lossHistory: [(received: Int, lost: Int)] = []
    private var lastTotals: (received: Int, lost: Int) = (0, 0)

    init() {
        let suffix = String(format: "%04x", UInt16.random(in: .min ... .max))
        localName = "\(UIDevice.current.name)#\(suffix)"
    }

    static func displayName(from serviceName: String) -> String {
        guard let hashIndex = serviceName.lastIndex(of: "#") else { return serviceName }
        return String(serviceName[..<hashIndex])
    }

    func start() {
        queue.async { self.startLocked() }
    }

    func stop() {
        queue.async {
            self.stopLocked()
            self.publishState(.stopped)
        }
    }

    func restart() {
        queue.async {
            self.stopLocked()
            self.startLocked()
        }
    }

    /// Thread-safe; called from the audio capture queue with one wire frame,
    /// or with empty Data as a mute keepalive.
    func send(frame: Data) {
        queue.async {
            guard let outbound = self.outbound, self.outboundReady else { return }
            var datagram = withUnsafeBytes(of: self.txSequence.bigEndian) { Data($0) }
            datagram.append(frame)
            self.txSequence &+= 1
            outbound.send(content: datagram, completion: .contentProcessed { [weak self] error in
                guard let self, let error else { return }
                // Only errors that mean "the peer endpoint is gone" justify
                // a reconnect; queue-full style hiccups (ENOBUFS, EAGAIN on
                // a congested AWDL link) are just one dropped frame.
                if case .posix(let code) = error,
                   code == .ECONNREFUSED || code == .EHOSTUNREACH
                       || code == .EHOSTDOWN || code == .ENETUNREACH {
                    self.handleSendError(on: outbound)
                }
            })
        }
    }

    // MARK: - Lifecycle (all on `queue`)

    private func startLocked() {
        guard !started else { return }
        started = true
        publishState(.searching)
        startListener()
        startBrowser()
        startStatsTimer()
    }

    private func stopLocked() {
        started = false
        statsTimer?.cancel()
        statsTimer = nil
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        inbound?.cancel()
        inbound = nil
        teardownOutbound()
        txSequence = 0
        highestRxSequence = nil
        recentlyFailedPeers = [:]
        stats = Stats()
        lastAudioDate = nil
        lastKeepaliveDate = nil
        lossHistory = []
        lastTotals = (0, 0)
        // boundPort is intentionally kept: a restarted listener must come
        // back on the same port or the peer's pinned flow goes into a void.
    }

    private func makeParameters() -> NWParameters {
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        parameters.serviceClass = .interactiveVoice
        parameters.allowLocalEndpointReuse = true
        return parameters
    }

    private func checkPermissionDenied(_ error: NWError) {
        if case .dns(let code) = error, code == Self.dnsPolicyDenied {
            publishHint(
                "Local Network permission is blocked. Enable it in Settings → Privacy & Security → Local Network → BTPhone, then tap Restart connection."
            )
        }
    }

    // MARK: - Listener (receives the peer's audio)

    private func scheduleListenerRetry() {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.started, self.listener == nil else { return }
            self.startListener()
        }
    }

    private func startListener() {
        let listener: NWListener
        do {
            if let port = boundPort {
                do {
                    listener = try NWListener(using: makeParameters(), on: port)
                } catch {
                    boundPort = nil
                    listener = try NWListener(using: makeParameters())
                }
            } else {
                listener = try NWListener(using: makeParameters())
            }
        } catch {
            scheduleListenerRetry()
            return
        }

        listener.service = NWListener.Service(name: localName, type: Self.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            self?.adoptInbound(connection)
        }
        var everReady = false
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, self.listener === listener, self.started else { return }
            switch state {
            case .ready:
                everReady = true
                if self.boundPort == nil {
                    self.boundPort = listener.port
                }
            case .waiting(let error):
                self.checkPermissionDenied(error)
            case .failed:
                // A pinned port that never bound is likely held by another
                // process — fall back to an ephemeral port next attempt.
                if !everReady {
                    self.boundPort = nil
                }
                self.listener = nil
                listener.cancel()
                self.scheduleListenerRetry()
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener

        // Escape hatch for a pinned bind that hangs in .waiting instead of
        // failing outright: after 5 s without .ready, rebind ephemeral.
        if boundPort != nil {
            queue.asyncAfter(deadline: .now() + 5) { [weak self, weak listener] in
                guard let self, let listener, self.listener === listener,
                      self.started, !everReady else { return }
                self.boundPort = nil
                self.listener = nil
                listener.cancel()
                self.startListener()
            }
        }
    }

    private func adoptInbound(_ connection: NWConnection) {
        inbound?.cancel()
        inbound = connection
        // New flow (e.g. the peer relaunched the app) restarts its sequence.
        highestRxSequence = nil
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.inbound === connection else { return }
            switch state {
            case .failed, .cancelled:
                self.inbound = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLoop(on: connection)
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, self.inbound === connection else { return }
            if let data, data.count >= Wire.headerBytes {
                self.handleDatagram(data)
            }
            if error == nil {
                self.receiveLoop(on: connection)
            } else {
                self.inbound = nil
            }
        }
    }

    private func handleDatagram(_ data: Data) {
        let sequence = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian

        if let highest = highestRxSequence {
            if sequence <= highest && highest - sequence <= 5_000 {
                // Late or duplicate packet. Writing it now would garble
                // already-played audio, so drop it.
                stats.lateDrops += 1
                return
            }
            if sequence > highest {
                // Cap the counted gap: a stall/reconnect isn't packet loss.
                stats.packetsLost += Int(min(sequence - highest - 1, 500))
            }
            // A sequence far in the past means the peer restarted its
            // stream on the same flow: fall through and resync to it.
        }
        highestRxSequence = sequence
        stats.packetsReceived += 1

        let payload = data.dropFirst(Wire.headerBytes)
        if payload.isEmpty {
            lastKeepaliveDate = Date() // peer is muted but alive
        } else {
            lastAudioDate = Date()
            onPayload?(payload)
        }
    }

    // MARK: - Browser (carries my audio to the peer)

    private func scheduleBrowserRetry() {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.started, self.browser == nil else { return }
            self.startBrowser()
        }
    }

    private func startBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.evaluate(results: results)
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self, let browser, self.browser === browser, self.started else { return }
            switch state {
            case .ready:
                self.publishHint(nil)
            case .waiting(let error):
                self.checkPermissionDenied(error)
            case .failed:
                self.browser = nil
                browser.cancel()
                self.scheduleBrowserRetry()
            default:
                break
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func evaluate(results: Set<NWBrowser.Result>) {
        guard started else { return }
        let candidates: [(name: String, endpoint: NWEndpoint)] = results.compactMap { result in
            guard case let .service(name, _, _, _) = result.endpoint, name != localName else {
                return nil
            }
            return (name, result.endpoint)
        }

        if let current = outboundPeerName {
            if candidates.contains(where: { $0.name == current }) {
                return // keep the existing connection
            }
            teardownOutbound() // peer's advertisement vanished
        }

        // Deterministic pick if several phones are around, but deprioritize
        // names that just failed to connect — a battery-died peer's stale
        // Bonjour record can linger next to its fresh post-reboot one.
        let now = Date()
        recentlyFailedPeers = recentlyFailedPeers.filter { now.timeIntervalSince($0.value) < 10 }
        guard let target = candidates.min(by: {
            let aFailed = recentlyFailedPeers[$0.name] != nil
            let bFailed = recentlyFailedPeers[$1.name] != nil
            if aFailed != bFailed { return !aFailed }
            return $0.name < $1.name
        }) else {
            publishState(.searching)
            return
        }
        connect(to: target.endpoint, named: target.name)
    }

    private func connect(to endpoint: NWEndpoint, named name: String) {
        teardownOutbound()
        let display = Self.displayName(from: name)
        publishState(.connecting(peer: display))

        let connection = NWConnection(to: endpoint, using: makeParameters())
        outbound = connection
        outboundPeerName = name
        outboundReady = false

        var waitingTimeoutArmed = false
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.outbound === connection else { return }
            switch state {
            case .ready:
                self.outboundReady = true
                waitingTimeoutArmed = false
                self.recentlyFailedPeers.removeValue(forKey: name)
                self.publishState(.connected(peer: display))
            case .failed, .cancelled:
                self.recentlyFailedPeers[name] = Date()
                self.teardownOutbound()
                self.publishState(.searching)
                self.scheduleReconnect()
            case .waiting:
                self.outboundReady = false
                self.publishState(.connecting(peer: display))
                // A UDP connection can sit in .waiting forever (e.g. a stale
                // Bonjour record for a peer that died without a goodbye).
                // Give it 5 s, then move on to another candidate.
                if !waitingTimeoutArmed {
                    waitingTimeoutArmed = true
                    self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self, self.started,
                              self.outbound === connection, !self.outboundReady else { return }
                        self.recentlyFailedPeers[name] = Date()
                        self.teardownOutbound()
                        self.publishState(.searching)
                        self.scheduleReconnect()
                    }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// A send error means the peer's listener moved or died while the flow
    /// stayed "ready" (UDP has no liveness). Reconnect through a fresh
    /// Bonjour resolution, which picks up the peer's current port.
    private func handleSendError(on connection: NWConnection) {
        guard started, outbound === connection else { return }
        teardownOutbound()
        publishState(.searching)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.started, self.outbound == nil else { return }
            if let results = self.browser?.browseResults {
                self.evaluate(results: results)
            }
        }
    }

    private func teardownOutbound() {
        outbound?.stateUpdateHandler = nil
        outbound?.cancel()
        outbound = nil
        outboundPeerName = nil
        outboundReady = false
    }

    // MARK: - Stats

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            self.stats.receivingAudio =
                self.lastAudioDate.map { now.timeIntervalSince($0) < 1.5 } ?? false
            // Wider window than receivingAudio: keepalives pause for a
            // couple of seconds during the muted phone's audio restarts,
            // and that must not flash a scary "no audio" warning.
            self.stats.peerMuted = !self.stats.receivingAudio &&
                (self.lastKeepaliveDate.map { now.timeIntervalSince($0) < 5 } ?? false)

            self.lossHistory.append((
                received: self.stats.packetsReceived - self.lastTotals.received,
                lost: self.stats.packetsLost - self.lastTotals.lost
            ))
            self.lastTotals = (self.stats.packetsReceived, self.stats.packetsLost)
            if self.lossHistory.count > 10 {
                self.lossHistory.removeFirst(self.lossHistory.count - 10)
            }
            let received = self.lossHistory.reduce(0) { $0 + $1.received }
            let lost = self.lossHistory.reduce(0) { $0 + $1.lost }
            self.stats.recentLossPercent =
                (received + lost) > 0 ? Double(lost) * 100 / Double(received + lost) : 0

            let snapshot = self.stats
            DispatchQueue.main.async { self.onStats?(snapshot) }
        }
        timer.resume()
        statsTimer = timer
    }

    private func publishState(_ state: LinkState) {
        DispatchQueue.main.async { self.onState?(state) }
    }

    private func publishHint(_ hint: String?) {
        DispatchQueue.main.async { self.onHint?(hint) }
    }
}
