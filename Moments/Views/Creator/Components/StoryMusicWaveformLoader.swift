import AVFoundation

actor StoryMusicWaveformCache {
    static let shared = StoryMusicWaveformCache()
    private var values: [String: [Float]] = [:]
    func value(for key: String) -> [Float]? { values[key] }
    func insert(_ peaks: [Float], for key: String) {
        if values.count >= 12 { values.removeAll() }
        values[key] = peaks
    }
}

enum StoryMusicWaveformLoader {
    /// Decode MP3 at its native rate/channel layout; AVAssetReader cannot
    /// reliably perform the forced 8 kHz mono conversion previously requested.
    static func load(url: URL, duration: Double) async throws -> [Float] {
        let cacheKey = url.host.map { $0 + url.path } ?? url.path
        if let cached = await StoryMusicWaveformCache.shared.value(for: cacheKey) { return cached }
        let (file, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 40 * 1024 * 1024 else { throw StoryMusicCatalog.CatalogError.invalidResponse }
        let task = Task.detached(priority: .utility) {
            let audio = try AVAudioFile(forReading: file, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = audio.processingFormat
            guard format.sampleRate.isFinite, format.sampleRate > 0,
                  format.channelCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)
            else { throw StoryMusicCatalog.CatalogError.invalidResponse }
            let bucketSize = max(Int(Double(audio.length) / 1200), 1)
            var peaks: [Float] = []
            var energy: Double = 0
            var count = 0
            while audio.framePosition < audio.length {
                try Task.checkCancellation()
                try audio.read(into: buffer)
                guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
                for frame in 0..<Int(buffer.frameLength) {
                    var frameEnergy: Double = 0
                    for channel in 0..<Int(format.channelCount) {
                        let sample = Double(channels[channel][frame])
                        if sample.isFinite { frameEnergy += sample * sample }
                    }
                    energy += frameEnergy / Double(format.channelCount)
                    count += 1
                    if count == bucketSize {
                        peaks.append(Float(sqrt(energy / Double(count))))
                        energy = 0
                        count = 0
                    }
                }
            }
            if count > 0 { peaks.append(Float(sqrt(energy / Double(count)))) }
            guard !peaks.isEmpty else { throw StoryMusicCatalog.CatalogError.invalidResponse }
            let maximum = peaks.max() ?? 0
            return maximum > 0 ? peaks.map { $0 / maximum } : peaks
        }
        let peaks = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        await StoryMusicWaveformCache.shared.insert(peaks, for: cacheKey)
        return peaks
    }
}
