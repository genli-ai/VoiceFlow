import AVFoundation

/// 麦克风录音，实时重采样为 16kHz 单声道 Float32（识别模型需要的格式）
final class AudioRecorder {

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?
    private var samples: [Float] = []
    private let lock = NSLock()

    /// 录音音量回调（0~1），用于悬浮窗波形动画。注意：在音频线程回调。
    var onLevel: ((Float) -> Void)?

    private(set) var isRecording = false

    func start() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)

        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw VFError("没有可用的麦克风输入设备")
        }
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16000,
                                            channels: 1,
                                            interleaved: false) else {
            throw VFError("无法创建音频格式")
        }
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw VFError("无法创建音频转换器")
        }

        lock.lock()
        samples.removeAll()
        lock.unlock()

        self.engine = engine
        self.converter = converter
        self.outFormat = outFormat

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.engine = nil
            self.converter = nil
            self.outFormat = nil
            throw VFError("无法启动录音：\(error.localizedDescription)")
        }

        isRecording = true
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter = converter, let outFormat = outFormat else { return }

        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        guard status != .error, error == nil, let channel = out.floatChannelData else { return }

        let n = Int(out.frameLength)
        guard n > 0 else { return }

        let ptr = UnsafeBufferPointer(start: channel[0], count: n)
        lock.lock()
        samples.append(contentsOf: ptr)
        lock.unlock()

        // 计算 RMS 音量
        var sum: Float = 0
        for v in ptr { sum += v * v }
        let rms = (sum / Float(n)).squareRoot()
        onLevel?(min(1.0, rms * 14))
    }

    /// 停止并返回 16kHz 采样
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        outFormat = nil
        isRecording = false

        lock.lock()
        let result = samples
        samples.removeAll()
        lock.unlock()
        return result
    }

    var recordedDuration: Double {
        lock.lock()
        let count = samples.count
        lock.unlock()
        return Double(count) / 16000.0
    }
}
