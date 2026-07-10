import AVFoundation

/// Full-duplex voice pipeline built on AVAudioEngine with Apple's
/// voice-processing I/O unit (echo cancellation + AGC + noise suppression).
///
/// Capture: mic -> input tap -> capture queue -> AVAudioConverter -> 16 kHz
///          mono Int16 frames handed to `onCapturedFrame` (20 ms each).
/// Playback: network payloads -> JitterBuffer -> AVAudioSourceNode -> mixer.
final class IntercomAudio {
    /// Called on the capture queue with one 640-byte wire frame at a time.
    /// Set before calling start(); re-read on every start.
    var onCapturedFrame: ((Data) -> Void)?

    let jitter = JitterBuffer(
        capacitySamples: Int(Wire.sampleRate) / 4, // hard latency cap: 250 ms
        prebufferSamples: Int(Wire.sampleRate) * 60 / 1000 // 60 ms cushion
    )

    private(set) var isRunning = false
    var engineRunning: Bool { engine.isRunning }

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let scratchCapacity = 8192
    private let scratch: UnsafeMutablePointer<Int16>

    /// All capture-side state (converter, frame accumulator) lives in one
    /// context object per engine generation, touched only on this serial
    /// queue. That keeps stop()/start() on the main thread from racing an
    /// in-flight tap callback.
    private let captureQueue = DispatchQueue(label: "btphone.capture", qos: .userInteractive)
    private var captureContext: CaptureContext?

    private let wireInt16Format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Wire.sampleRate,
        channels: 1,
        interleaved: true
    )!
    private let wireFloatFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Wire.sampleRate,
        channels: 1,
        interleaved: false
    )!

    var outputVolume: Float = 1.0 {
        didSet { engine.mainMixerNode.outputVolume = outputVolume }
    }

    var isMicMuted: Bool = false {
        didSet {
            if engine.isRunning {
                engine.inputNode.isVoiceProcessingInputMuted = isMicMuted
            }
        }
    }

    init() {
        scratch = .allocate(capacity: scratchCapacity)
        scratch.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit {
        scratch.deallocate()
    }

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // HFP only, deliberately no A2DP: with a helmet headset we need its
        // boom mic, and A2DP routes would fall back to the phone's own mic
        // (useless inside a pocket).
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
        if #available(iOS 26.0, *) {
            options.insert(.allowBluetoothHFP)
        } else {
            options.insert(.allowBluetooth)
        }
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func start() throws {
        guard !isRunning else { return }
        try configureSession()

        // Fresh engine each start: after route changes (helmet headset
        // connecting) the old graph's formats are stale.
        engine = AVAudioEngine()
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)

        let jitter = self.jitter
        let scratch = self.scratch
        let scratchCapacity = self.scratchCapacity
        let node = AVAudioSourceNode(format: wireFloatFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let n = Int(frameCount)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let rawOut = buffers[0].mData else { return noErr }
            let out = rawOut.assumingMemoryBound(to: Float.self)
            guard n <= scratchCapacity else {
                out.update(repeating: 0, count: n)
                return noErr
            }
            jitter.read(into: scratch, count: n)
            for i in 0..<n {
                out[i] = Float(scratch[i]) / 32768.0
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: wireFloatFormat)
        sourceNode = node
        engine.mainMixerNode.outputVolume = outputVolume

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "BTPhone", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone is not available yet."]
            )
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: wireInt16Format) else {
            throw NSError(
                domain: "BTPhone", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported microphone format."]
            )
        }

        let context = CaptureContext(converter: converter, onFrame: onCapturedFrame ?? { _ in })
        captureContext = context
        let captureQueue = self.captureQueue
        input.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { buffer, _ in
            captureQueue.async {
                guard context.active else { return }
                context.process(buffer)
            }
        }

        engine.prepare()
        try engine.start()
        input.isVoiceProcessingInputMuted = isMicMuted
        jitter.reset()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        if let context = captureContext {
            captureQueue.async { context.active = false }
            captureContext = nil
        }
        engine.stop()
        if let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        jitter.reset()
        isRunning = false
    }

    /// Feed one received wire payload (Int16 little-endian samples) into the
    /// playback path. Called from the network queue.
    func enqueuePlayback(_ payload: Data) {
        let sampleCount = payload.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return }
        // Copy out of Data: the payload is a slice of the datagram and is not
        // guaranteed to be 2-byte aligned.
        var samples = [Int16](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { dst in
            payload.copyBytes(to: dst, count: sampleCount * MemoryLayout<Int16>.size)
        }
        samples.withUnsafeBufferPointer { src in
            jitter.write(src.baseAddress!, count: src.count)
        }
    }
}

/// Capture-side state for one engine generation. `active` and all other
/// members are only ever touched on IntercomAudio's capture queue.
private final class CaptureContext {
    var active = true

    private let converter: AVAudioConverter
    private let onFrame: (Data) -> Void
    private var pending: [Int16] = []

    init(converter: AVAudioConverter, onFrame: @escaping (Data) -> Void) {
        self.converter = converter
        self.onFrame = onFrame
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let outputFormat = converter.outputFormat
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, converted.frameLength > 0,
              let channel = converted.int16ChannelData else { return }

        pending.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(converted.frameLength)))
        while pending.count >= Wire.frameSamples {
            let frame = pending.prefix(Wire.frameSamples).withUnsafeBufferPointer { Data(buffer: $0) }
            pending.removeFirst(Wire.frameSamples)
            onFrame(frame)
        }
    }
}
