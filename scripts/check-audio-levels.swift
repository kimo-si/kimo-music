import AVFoundation

@main
struct AudioLevelsCheck {
    // 与 PlaybackAudioLevels.swift 一起编译，验证真实音频旁路采样。
    @MainActor
    static func main() async throws {
        try await checkSignal(amplitude: 0.25)
        try await checkSignal(amplitude: 0)
        print("真实音频采样检查通过：整排实时更新、连续起伏、静音无响应、过期衰减、替换清理")
    }

    // 创建临时音源并在播放开始后接入采样，与产品安装顺序一致。
    @MainActor
    private static func checkSignal(amplitude: Float) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSignal(url: url, amplitude: amplitude)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        player.play()
        let tracks = try await item.asset.loadTracks(withMediaType: .audio)
        let levels = PlaybackAudioLevels()
        item.audioMix = levels.makeMix(track: tracks[0])
        precondition(item.audioMix != nil, "tap 创建失败")
        try await Task.sleep(for: .seconds(1))
        let peak = levels.snapshot(at: ProcessInfo.processInfo.systemUptime).max() ?? 0
        precondition(amplitude > 0 ? peak > 0.1 : peak == 0, "采样不符合音源，peak=\(peak)")
        // 验证整排音柱使用当前片段，且持续响应强弱变化。
        if amplitude > 0 { try await checkLiveUpdates(levels) }
        player.pause()
        precondition(player.rate == 0, "暂停不应被采样器干扰")
        let staleTime = ProcessInfo.processInfo.systemUptime + 1
        precondition(levels.snapshot(at: staleTime).allSatisfy { $0 == 0 }, "过期包络未衰减")
        player.replaceCurrentItem(with: nil)
    }

    // 固定间隔读取采样，防止重新退化为历史滚动或只更新首帧。
    private static func checkLiveUpdates(_ levels: PlaybackAudioLevels) async throws {
        var previous = levels.snapshot(at: ProcessInfo.processInfo.systemUptime)
        precondition(previous.allSatisfy { $0 > 0 }, "当前有声片段应立即更新全部音柱")
        var changedFrames = 0
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(60))
            let current = levels.snapshot(at: ProcessInfo.processInfo.systemUptime)
            let changes = zip(current, previous).filter { abs($0 - $1) > 0.015 }.count
            if changes > PlaybackAudioLevels.barCount / 2 { changedFrames += 1 }
            previous = current
        }
        precondition(changedFrames >= 3, "连续音频应驱动整排音柱变化，实际变化帧数：\(changedFrames)")
    }

    // 写入可控的正弦 PCM，测试无需网络、账号或用户音乐文件。
    private static func writeSignal(url: URL, amplitude: Float) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 4)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for index in 0..<Int(buffer.frameLength) {
                let time = Float(index) / 44100
                let pulse = 0.55 + 0.45 * sin(time * 2 * .pi * 3)
                buffer.floatChannelData![channel][index] = amplitude * pulse * sin(time * 2 * .pi * 440)
            }
        }
        let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: fileFormat.settings)
        try file.write(from: buffer)
    }
}
