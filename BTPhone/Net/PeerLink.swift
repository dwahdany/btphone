import Foundation
import Network
import WiFiAware
import os

/// Peer discovery and audio transport over Wi-Fi Aware (iOS 26).
///
/// Both phones publish AND subscribe the `_twoup._udp` service to their
/// paired devices, giving two independent one-way UDP flows: my browser
/// connects to your listener to carry my mic, yours connects to mine to
/// carry your mic. No role negotiation — both phones just run the app.
///
/// Unlike the old AWDL/Bonjour transport, Wi-Fi Aware links are paired,
/// authenticated, and encrypted by the system, and they keep running with
/// the screen locked as long as the app stays alive (our audio background
/// mode guarantees that).
///
/// Datagrams with an empty payload are mute keepalives: they keep the flow
/// (and the peer's "link is alive" signal) up while the mic is muted.
actor PeerLink {
    static let serviceName = "_twoup._udp"
    private static let log = Logger(subsystem: "com.wahdany.twoup", category: "PeerLink")

    enum LinkState: Equatable, Sendable {
        case stopped
        case unsupported
        case unpaired
        case searching
        case connecting(peer: String)
        case connected(peer: String)
    }

    struct Stats: Sendable {
        var packetsReceived: Int = 0
        var packetsLost: Int = 0
        var lateDrops: Int = 0
        /// Loss over roughly the last 10 seconds — what the UI shows.
        var recentLossPercent: Double = 0
        var receivingAudio: Bool = false
        /// The peer's flow is alive but it is deliberately sending silence.
        var peerMuted: Bool = false
    }

    // Callbacks. onPayload fires on the receive task (off-main); the rest
    // are delivered on the main queue.
    private var onPayload: (@Sendable (Data) -> Void)?
    private var onState: (@Sendable (LinkState) -> Void)?
    private var onStats: (@Sendable (Stats) -> Void)?
    private var onHint: (@Sendable (String?) -> Void)?
    private var onPairedChanged: (@Sendable (Bool) -> Void)?

    private var started = false
    private var hasPairedDevices = false
    private var hasMultiplePairs = false
    private var lastPublishedState: LinkState?
    private var searchingSince: Date?
    private var lastHint: String?
    /// Device IDs from the last WAPairedDevice snapshot; a CHANGE while
    /// running (fresh pairing) triggers a full link rebuild — sessions built
    /// on pre-pairing daemon state reliably wedge on first establishment.
    private var pairedSnapshot: Set<String>?
    private var lastAutoRestartDate: Date?
    /// Jittered so two phones can't fall into restart lockstep.
    private var stuckThreshold = TimeInterval.random(in: 12...18)

    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var pairMonitorTask: Task<Void, Never>?
    private var senderTask: Task<Void, Never>?
    private var inboundReceiveTask: Task<Void, Never>?

    private var inbound: NetworkConnection<UDP>?
    private var outbound: NetworkConnection<UDP>?
    private var outboundReady = false
    private var outboundBroken = false
    private var outboundReadySince: Date?

    private var txSequence: UInt32 = 0
    private var highestRxSequence: UInt32?
    private var stats = Stats()
    private var lastAudioDate: Date?
    private var lastKeepaliveDate: Date?
    // Send-side liveness: the peer's ACKs echo the highest sequence it
    // received from us. As long as that value keeps changing, our outbound
    // datapath demonstrably delivers.
    private var lastAckedValue: UInt32?
    private var lastAckProgressDate: Date?
    private var lossHistory: [(received: Int, lost: Int)] = []
    private var lastTotals: (received: Int, lost: Int) = (0, 0)

    // Mic frames enter here synchronously from the audio capture queue; the
    // sender task drains it. bufferingNewest keeps latency bounded if the
    // radio stalls: old frames are dropped, not queued.
    private nonisolated let outboxStream: AsyncStream<Data>
    private nonisolated let outbox: AsyncStream<Data>.Continuation

    init() {
        (outboxStream, outbox) = AsyncStream.makeStream(
            of: Data.self, bufferingPolicy: .bufferingNewest(8)
        )
    }

    deinit {
        outbox.finish()
        listenerTask?.cancel()
        browserTask?.cancel()
        statsTask?.cancel()
        pairMonitorTask?.cancel()
        senderTask?.cancel()
        inboundReceiveTask?.cancel()
    }

    func configure(
        onPayload: @escaping @Sendable (Data) -> Void,
        onState: @escaping @Sendable (LinkState) -> Void,
        onStats: @escaping @Sendable (Stats) -> Void,
        onHint: @escaping @Sendable (String?) -> Void,
        onPairedChanged: @escaping @Sendable (Bool) -> Void
    ) {
        self.onPayload = onPayload
        self.onState = onState
        self.onStats = onStats
        self.onHint = onHint
        self.onPairedChanged = onPairedChanged
    }

    /// Thread-safe; called from the audio capture queue with one wire frame,
    /// or with empty Data as a mute keepalive.
    nonisolated func send(frame: Data) {
        outbox.yield(frame)
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        guard WACapabilities.supportedFeatures.contains(.wifiAware) else {
            publish(.unsupported)
            return
        }
        started = true
        publish(.searching)
        pairMonitorTask = Task { await self.monitorPairedDevices() }
        listenerTask = Task { await self.listenerLoop() }
        browserTask = Task { await self.browserLoop() }
        statsTask = Task { await self.statsLoop() }
        if senderTask == nil {
            // Lives for the object's lifetime: an AsyncStream can only be
            // iterated once, so restarts must not recreate this task.
            senderTask = Task { await self.senderLoop() }
        }
    }

    func stop() {
        guard started else { return }
        started = false
        listenerTask?.cancel()
        listenerTask = nil
        browserTask?.cancel()
        browserTask = nil
        statsTask?.cancel()
        statsTask = nil
        pairMonitorTask?.cancel()
        pairMonitorTask = nil
        inboundReceiveTask?.cancel()
        inboundReceiveTask = nil
        inbound = nil
        outbound = nil
        outboundReady = false
        outboundBroken = false
        txSequence = 0
        highestRxSequence = nil
        stats = Stats()
        lastAudioDate = nil
        lastKeepaliveDate = nil
        lastAckedValue = nil
        lastAckProgressDate = nil
        lossHistory = []
        lastTotals = (0, 0)
        searchingSince = nil
        setHint(nil)
        publish(.stopped)
    }

    func restart() {
        stop()
        start()
    }

    // MARK: - Paired devices

    private func monitorPairedDevices() async {
        do {
            for try await devices in WAPairedDevice.allDevices {
                guard started else { return }
                hasPairedDevices = !devices.isEmpty
                hasMultiplePairs = devices.count > 1
                let paired = hasPairedDevices
                if let onPairedChanged {
                    DispatchQueue.main.async { onPairedChanged(paired) }
                }
                if !paired {
                    publish(.unpaired)
                } else if lastPublishedState == .unpaired {
                    publish(.searching)
                }

                let snapshot = Set(devices.keys.map { String(describing: $0) })
                let changed = pairedSnapshot != nil && snapshot != pairedSnapshot
                pairedSnapshot = snapshot
                if changed, paired {
                    // Restart cancels this task; the loop ends via the
                    // cancellation check on its next iteration while the
                    // fresh monitor picks up from the stored snapshot.
                    Self.log.info("pairing set changed — rebuilding link")
                    restart()
                }
            }
        } catch {
            // Monitoring failing is non-fatal; pairing state just goes stale.
        }
    }

    // MARK: - Listener (receives the peer's audio)

    private func listenerLoop() async {
        while started && !Task.isCancelled {
            guard hasPairedDevices,
                  let service = WAPublishableService.allServices[Self.serviceName] else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            do {
                let provider: any ListenerProvider = .wifiAware(
                    .connecting(to: service, from: .allPairedDevices, datapath: .realtime)
                )
                let listener = try NetworkListener(
                    for: provider,
                    using: .parameters { UDP() }
                        .wifiAware { $0.performanceMode = .realtime }
                        .serviceClass(.interactiveVoice)
                )
                try await listener.run { connection in
                    self.adoptInbound(connection)
                }
            } catch {
                // publisherTimeout after idle, transient failures: re-arm.
                Self.log.error("listener ended: \(error, privacy: .public)")
                self.reportIfActionable(error)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // NetworkConnection has no close()/cancel(); teardown happens when the
    // last reference drops. That only works if NOTHING awaits on the
    // connection — a send() parked on a never-establishing connection keeps
    // it (and its Wi-Fi Aware datapath) alive forever. Hence the invariant
    // throughout this file: only ever await send()/receive() on a .ready
    // connection, and drive establishment with the explicit start().

    private func adoptInbound(_ connection: NetworkConnection<UDP>) {
        guard started else { return }
        Self.log.info("listener: adopted inbound connection")
        inboundReceiveTask?.cancel()
        inbound = connection
        // New flow (e.g. the peer relaunched the app) restarts its sequence.
        highestRxSequence = nil
        inboundReceiveTask = Task { await self.receiveLoop(on: connection) }
    }

    private func receiveLoop(on connection: NetworkConnection<UDP>) async {
        do {
            while started && !Task.isCancelled {
                let message = try await connection.receive()
                handleDatagram(message.content)
            }
        } catch {
            if inbound === connection {
                inbound = nil
            }
        }
    }

    private func handleDatagram(_ data: Data) {
        guard data.count >= Wire.headerBytes else { return }
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
        switch payload.count {
        case 0:
            lastKeepaliveDate = Date() // peer is muted but alive
        case Wire.ackBytes:
            let acked = payload.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
            // Any change counts as progress (a peer app restart resyncs and
            // can make the value jump backwards).
            if acked != Wire.ackNone && acked != lastAckedValue {
                lastAckedValue = acked
                lastAckProgressDate = Date()
            }
        default:
            lastAudioDate = Date()
            onPayload?(payload)
        }
    }

    // MARK: - Browser (carries my audio to the peer)

    private func browserLoop() async {
        while started && !Task.isCancelled {
            guard hasPairedDevices,
                  let service = WASubscribableService.allServices[Self.serviceName] else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            do {
                let browser = NetworkBrowser(
                    for: .wifiAware(.connecting(to: .allPairedDevices, from: service))
                )
                let endpoint: WAEndpoint = try await browser.run { endpoints in
                    if let first = endpoints.first {
                        return .finish(first)
                    }
                    return .continue
                }
                Self.log.info("browser: discovered endpoint \(String(describing: endpoint), privacy: .public)")
                try await runOutbound(to: endpoint)
            } catch {
                Self.log.error("browser/outbound ended: \(error, privacy: .public)")
                self.reportIfActionable(error)
            }
            publish(hasPairedDevices ? .searching : .unpaired)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func runOutbound(to endpoint: WAEndpoint) async throws {
        let peer = endpoint.device.name
            ?? endpoint.device.pairingInfo?.pairingName
            ?? String(localized: "paired iPhone")
        publish(.connecting(peer: peer))
        Self.log.info("outbound: connecting to \(peer, privacy: .public)")

        let connection = NetworkConnection(
            to: endpoint,
            using: .parameters { UDP() }
                .wifiAware { $0.performanceMode = .realtime }
                .serviceClass(.interactiveVoice)
        )
        connection.onStateUpdate { [weak self] conn, state in
            Self.log.info("outbound state: \(String(describing: state), privacy: .public)")
            guard let self else { return }
            Task { await self.outboundStateChanged(conn, isReady: state == .ready, peer: peer) }
        }
        // A UDP connection establishes on first use. Drive that from a
        // dedicated throwaway task that nothing awaits: the long-lived
        // sender/stats loops must never park on a connection that might
        // never come up (see invariant above).
        var hello = withUnsafeBytes(of: txSequence.bigEndian) { Data($0) }
        hello.append(
            withUnsafeBytes(of: (highestRxSequence ?? Wire.ackNone).bigEndian) { Data($0) }
        )
        txSequence &+= 1
        let establish = Task { try? await connection.send(hello) }
        // Cancellation can throw us out of ANY await below (auto-restart
        // cancels browserTask mid-sleep); without this, the orphaned hello
        // task keeps the never-ready connection and its datapath alive
        // forever. The explicit cancels on the exit paths become redundant.
        defer { establish.cancel() }

        outbound = connection
        outboundBroken = false
        outboundReady = false

        // Wait (bounded) for the datapath. Healthy establishment takes well
        // under 1.5 s; an attempt stuck in .preparing usually means the
        // peer's daemon still holds the previous session's dead flow, and
        // the NEXT attempt then succeeds immediately — so give up fast.
        var waitedSeconds = 0
        while started && !Task.isCancelled {
            let state = connection.state
            if state == .ready { break }
            if case .failed(let error) = state {
                establish.cancel()
                outbound = nil
                throw error
            }
            if case .cancelled = state {
                establish.cancel()
                outbound = nil
                return
            }
            waitedSeconds += 1
            if waitedSeconds >= 5 {
                Self.log.error("outbound: never became ready, giving up")
                establish.cancel()
                outbound = nil
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        guard started, !Task.isCancelled else {
            establish.cancel()
            outbound = nil
            return
        }
        outboundReady = true

        // Hold this flow until it breaks (send failure, state change, or
        // ACK-liveness); the framework fails the connection when the peer
        // genuinely goes away.
        while started && !Task.isCancelled && !outboundBroken {
            if connection.state != .ready { break }
            try await Task.sleep(for: .seconds(1))
        }
        Self.log.info("outbound: flow ended (broken=\(self.outboundBroken), state=\(String(describing: connection.state), privacy: .public))")
        outboundReady = false
        outboundReadySince = nil
        outbound = nil
    }

    private func outboundStateChanged(
        _ connection: NetworkConnection<UDP>, isReady: Bool, peer: String
    ) {
        guard outbound === connection else { return }
        if isReady {
            outboundReadySince = Date()
            publish(.connected(peer: peer))
            setHint(nil)
        }
    }

    private func senderLoop() async {
        for await frame in outboxStream {
            guard started, outboundReady, let connection = outbound,
                  connection.state == .ready else { continue }
            var datagram = withUnsafeBytes(of: txSequence.bigEndian) { Data($0) }
            datagram.append(frame)
            txSequence &+= 1
            do {
                try await connection.send(datagram)
            } catch {
                // Datapath died; runOutbound notices and re-browses.
                Self.log.error("send failed: \(error, privacy: .public)")
                outboundBroken = true
                outboundReady = false
            }
        }
    }

    // MARK: - Stats

    private func statsLoop() async {
        while started && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard started else { return }
            let now = Date()

            // Send an ACK over the outbound once per second, regardless of
            // audio state: it keeps the flow alive and gives the peer proof
            // its packets arrive. Only on a .ready connection — a send
            // awaiting establishment would park forever (see invariant).
            if let connection = outbound, connection.state == .ready {
                var datagram = withUnsafeBytes(of: txSequence.bigEndian) { Data($0) }
                datagram.append(
                    withUnsafeBytes(of: (highestRxSequence ?? Wire.ackNone).bigEndian) { Data($0) }
                )
                txSequence &+= 1
                Task { try? await connection.send(datagram) }
            }

            // Send-side liveness: a zombie datapath (peer process died and
            // came back) keeps reporting "ready" and swallowing sends. If
            // the peer's ACKs stop confirming our packets for 10 s, our
            // outbound is dead — tear it down and reconnect through a
            // fresh browse. (We send at least the 1/s ACKs above, so the
            // acked value must keep moving on a healthy flow.)
            if outboundReady, let since = outboundReadySince,
               now.timeIntervalSince(since) > 10,
               now.timeIntervalSince(lastAckProgressDate ?? .distantPast) > 10 {
                Self.log.error("liveness: no ACK progress for 10s — reconnecting outbound")
                outboundBroken = true
                outboundReady = false
            }

            stats.receivingAudio =
                lastAudioDate.map { now.timeIntervalSince($0) < 1.5 } ?? false
            // Wider window than receivingAudio: keepalives pause for a
            // couple of seconds during the muted phone's audio restarts,
            // and that must not flash a scary "no audio" warning.
            stats.peerMuted = !stats.receivingAudio &&
                (lastKeepaliveDate.map { now.timeIntervalSince($0) < 5 } ?? false)

            lossHistory.append((
                received: stats.packetsReceived - lastTotals.received,
                lost: stats.packetsLost - lastTotals.lost
            ))
            lastTotals = (stats.packetsReceived, stats.packetsLost)
            if lossHistory.count > 10 {
                lossHistory.removeFirst(lossHistory.count - 10)
            }
            let received = lossHistory.reduce(0) { $0 + $1.received }
            let lost = lossHistory.reduce(0) { $0 + $1.lost }
            stats.recentLossPercent =
                (received + lost) > 0 ? Double(lost) * 100 / Double(received + lost) : 0

            // Actionable hints — only while NOT connected: a healthy session
            // needs no warnings. Multi-pairing ambiguity outranks the
            // can't-reach hint; inbound audio still flowing suppresses the
            // latter (the peer is obviously nearby, only our outbound is
            // rebuilding).
            let isConnected: Bool = {
                if case .connected = lastPublishedState { return true }
                return false
            }()
            if isConnected {
                setHint(nil)
            } else if hasMultiplePairs {
                setHint(String(localized: "Multiple phones are paired — TwoUp connects to whichever responds first. Remove old pairings in iOS Settings."))
            } else if let since = searchingSince, now.timeIntervalSince(since) > 20,
                      !stats.receivingAudio {
                setHint(String(localized: "Can't reach the other phone. Make sure it's nearby with Wi-Fi on and TwoUp open."))
            } else {
                setHint(nil)
            }

            if let onStats {
                let snapshot = stats
                DispatchQueue.main.async { onStats(snapshot) }
            }

            // Escalating self-heal: browse-cycle retries sometimes never
            // recover from a wedged daemon session, but a full teardown and
            // rebuild (what the user achieves by END+START) does. If we've
            // been non-connected for a while with nothing coming in, do it
            // ourselves. The threshold is jittered per-process and a
            // cooldown prevents thrash; restart() resets searchingSince, so
            // each attempt gets a full window before the next.
            if let since = searchingSince,
               now.timeIntervalSince(since) > stuckThreshold,
               now.timeIntervalSince(lastAutoRestartDate ?? .distantPast) > 30 {
                lastAutoRestartDate = now
                Self.log.error("auto-restart: not connected for \(Int(now.timeIntervalSince(since)))s — rebuilding link")
                restart()
                return
            }
        }
    }

    // MARK: - Publishing

    private func publish(_ state: LinkState) {
        guard state != lastPublishedState else { return }
        lastPublishedState = state
        switch state {
        case .searching, .connecting:
            // .connecting keeps the clock running: a searching↔connecting
            // failure loop (endpoint found, establishment keeps dying) must
            // still surface the can't-reach hint.
            if searchingSince == nil { searchingSince = Date() }
        case .connected, .stopped, .unpaired, .unsupported:
            searchingSince = nil
        }
        if let onState {
            DispatchQueue.main.async { onState(state) }
        }
    }

    private func setHint(_ hint: String?) {
        guard hint != lastHint else { return }
        lastHint = hint
        if let onHint {
            DispatchQueue.main.async { onHint(hint) }
        }
    }

    private func reportIfActionable(_ error: Error) {
        guard let waError = (error as? NWError)?.wifiAware else { return }
        if case .noPairedDevices = waError {
            publish(.unpaired)
        }
    }
}
