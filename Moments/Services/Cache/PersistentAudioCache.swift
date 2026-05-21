import Foundation
import CryptoKit

final class PersistentAudioCache {
    static let shared = PersistentAudioCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("StoryAudio", isDirectory: true)
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    func cachedURL(for remoteURLString: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(filename(for: remoteURLString))
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func saveToCache(temporaryURL: URL, for remoteURLString: String) {
        let destinationURL = cacheDirectory.appendingPathComponent(filename(for: remoteURLString))
        if fileManager.fileExists(atPath: destinationURL.path) { return }

        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.copyItem(at: temporaryURL, to: destinationURL)
        }
    }

    func localURL(for remoteURL: URL) async throws -> URL {
        if let cached = cachedURL(for: remoteURL.absoluteString) {
            return cached
        }

        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
        saveToCache(temporaryURL: temporaryURL, for: remoteURL.absoluteString)
        return cacheDirectory.appendingPathComponent(filename(for: remoteURL.absoluteString))
    }

    func downloadAndCache(url: URL) {
        if cachedURL(for: url.absoluteString) != nil { return }

        URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            guard let self, let localURL, error == nil else { return }
            self.saveToCache(temporaryURL: localURL, for: url.absoluteString)
        }.resume()
    }

    func cleanupFiles(olderThan days: Int = 7) {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            for fileURL in files {
                let attributes = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                if let modDate = attributes.contentModificationDate, modDate < threshold {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
        }
    }

    func cacheSizeInBytes() -> Int {
        var totalSize = 0
        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = attributes.fileSize {
                    totalSize += fileSize
                }
            }
        }
        return totalSize
    }

    private func filename(for remoteURLString: String) -> String {
        hash(remoteURLString) + ".m4a"
    }

    private func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
