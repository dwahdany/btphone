import Foundation
import Network
import WiFiAware

/// Peer discovery and audio transport over Wi-Fi Aware (iOS 26).
///
/// Both phones publish AND subscribe the `_btphone._udp` service to their
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
    static let serviceName = "_btphone._udp"

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
    private var lastPublishedState: LinkState?

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

    private var txSequence: UInt32 = 0
    private var highestRxSequence: UInt32?
    private var stats = Stats()
    private var lastAudioDate: Date?
    private var lastKeepaliveDate: Date?
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
        lossHistory = []
        lastTotals = (0, 0)
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
                let paired = hasPairedDevices
                if let onPairedChanged {
                    DispatchQueue.main.async { onPairedChanged(paired) }
                }
                if !paired {
                    publish(.unpaired)
                } else if lastPublishedState == .unpaired {
                    publish(.searching)
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
                self.reportIfActionable(error)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func adoptInbound(_ connection: NetworkConnection<UDP>) {
        guard started else { return }
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
        if payload.isEmpty {
            lastKeepaliveDate = Date() // peer is muted but alive
        } else {
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
                try await runOutbound(to: endpoint)
            } catch {
                self.reportIfActionable(error)
            }
            publish(hasPairedDevices ? .searching : .unpaired)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func runOutbound(to endpoint: WAEndpoint) async throws {
        let peer = endpoint.device.name
            ?? endpoint.device.pairingInfo?.pairingName
            ?? "paired iPhone"
        publish(.connecting(peer: peer))

        let connection = NetworkConnection(
            to: endpoint,
            using: .parameters { UDP() }
                .wifiAware { $0.performanceMode = .realtime }
                .serviceClass(.interactiveVoice)
        )
        outbound = connection
        outboundReady = false
        outboundBroken = false

        // Wait (bounded) for the datapath to come up.
        var waitedMilliseconds = 0
        while started && !Task.isCancelled {
            let state = connection.state
            if state == .ready { break }
            if case .failed(let error) = state { throw error }
            if case .cancelled = state { return }
            try await Task.sleep(for: .milliseconds(100))
            waitedMilliseconds += 100
            if waitedMilliseconds >= 15_000 {
                outbound = nil
                return // give up; browse again
            }
        }
        guard started, !Task.isCancelled else { return }
        outboundReady = true
        publish(.connected(peer: peer))
        publishHint(nil)

        // Hold this flow until it breaks (send failure or state change);
        // the framework fails the connection when the peer goes away.
        while started && !Task.isCancelled {
            if outboundBroken || connection.state != .ready { break }
            try await Task.sleep(for: .seconds(1))
        }
        outboundReady = false
        outbound = nil
    }

    private func senderLoop() async {
        for await frame in outboxStream {
            guard started, outboundReady, let connection = outbound else { continue }
            var datagram = withUnsafeBytes(of: txSequence.bigEndian) { Data($0) }
            datagram.append(frame)
            txSequence &+= 1
            do {
                try await connection.send(datagram)
            } catch {
                // Datapath died; runOutbound notices and re-browses.
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

            if let onStats {
                let snapshot = stats
                DispatchQueue.main.async { onStats(snapshot) }
            }
        }
    }

    // MARK: - Publishing

    private func publish(_ state: LinkState) {
        guard state != lastPublishedState else { return }
        lastPublishedState = state
        if let onState {
            DispatchQueue.main.async { onState(state) }
        }
    }

    private func publishHint(_ hint: String?) {
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
