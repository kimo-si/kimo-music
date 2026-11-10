import AVFoundation
import MediaToolbox

/// 音频线程只记录音量包络，界面按需读取；不修改任何播放样本。
final class PlaybackAudioLevels: @unchecked Sendable {
    static let barCount = 64
    private static let sampleInterval = 1.0 / 30
    private static let staleInterval = 0.15
    private static let releaseFactor = 0.45
    private static let displayGain = 1.6
    private let lock = NSLock()
    private var levels = [Double](repeating: 0, count: barCount)
    private var updatedAt: TimeInterval = 0
    private var supportsFloatPCM = false

    // 读取同一音频片段的包络；缓冲或无新音频时快速衰减。
    func snapshot(at time: TimeInterval) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        let decay = max(0, 1 - max(0, time - updatedAt - Self.staleInterval) / Self.staleInterval)
        return levels.map { $0 * decay }
    }

    // 创建旁路采样混音；创建失败时保留原本的播放能力。
    func makeMix(track: AVAssetTrack) -> AVAudioMix? {
        var callbacks = makeCallbacks()
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                              kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else { return nil }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    // 由 tap 持有采样器直至 finalize，避免切歌后音频回调访问释放的对象。
    private func makeCallbacks() -> MTAudioProcessingTapCallbacks {
        MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: { _, info, storage in
                guard let info else { return }
                storage.pointee = Unmanaged<PlaybackAudioLevels>.fromOpaque(info).retain().toOpaque()
            },
            finalize: { tap in
                Unmanaged<PlaybackAudioLevels>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                PlaybackAudioLevels.owner(of: tap).prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                // 先原样取得音频，再旁路计算包络，保证声音不被改变。
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut)
                guard status == noErr, framesOut.pointee > 0 else { return }
                PlaybackAudioLevels.owner(of: tap).consume(buffers)
            }
        )
    }

    // 从 tap 的专属存储取回生命周期受其保护的采样器。
    private static func owner(of tap: MTAudioProcessingTap) -> PlaybackAudioLevels {
        Unmanaged<PlaybackAudioLevels>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    // 只读取原生 Float32 PCM；其他格式静默降级，避免错误解释内存。
    private func prepare(_ format: AudioStreamBasicDescription) {
        supportsFloatPCM = format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
            && format.mBitsPerChannel == 32
    }

    // 限制采样频率并使用非阻塞锁，界面读取不能阻塞实时音频线程。
    private func consume(_ buffers: UnsafeMutablePointer<AudioBufferList>) {
        guard supportsFloatPCM, lock.try() else { return }
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - updatedAt >= Self.sampleInterval else { return }
        // 每次更新整排音柱，避免将旧音量逐格滚动误作实时起伏。
        for index in levels.indices {
            let level = Self.envelope(in: buffers, at: index)
            levels[index] = max(level, levels[index] * Self.releaseFactor)
        }
        updatedAt = now
    }

    // 将当前 PCM 片段分段计算能量；按帧划分以兼容交错和非交错声道。
    private static func envelope(in buffers: UnsafeMutablePointer<AudioBufferList>, at index: Int) -> Double {
        var energy = 0.0
        var count = 0
        for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let length = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let channels = max(1, Int(buffer.mNumberChannels))
            let frames = length / channels
            let start = frames * index / Self.barCount * channels
            let end = min(length, max(start + channels, frames * (index + 1) / Self.barCount * channels))
            for offset in start..<end {
                let sample = Double(samples[offset])
                guard sample.isFinite else { continue }
                energy += sample * sample
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return min(1, pow(sqrt(energy / Double(count)), 0.75) * Self.displayGain)
    }
}
