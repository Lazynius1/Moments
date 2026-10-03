import Foundation
import CryptoKit

final class PersistentAudioCache {
    static let shared = PersistentAudioCache()

    private let fileLock = NSLock()
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

    @discardableResult
    private func saveToCache(temporaryURL: URL, for remoteURLString: String) throws -> URL {
        try fileLock.withLock {
            let destination = cacheDirectory.appendingPathComponent(filename(for: remoteURLString))
            if fileManager.fileExists(atPath: destination.path) { return destination }
            let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else { throw URLError(.zeroByteResource) }
            let staging = cacheDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
            defer { try? fileManager.removeItem(at: staging) }
            try fileManager.copyItem(at: temporaryURL, to: staging)
            try fileManager.moveItem(at: staging, to: destination)
            return destination
        }
    }

    private func validate(_ response: URLResponse) throws {
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
    }

    func localURL(for remoteURL: URL) async throws -> URL {
        if let cached = cachedURL(for: remoteURL.absoluteString) {
            return cached
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try Task.checkCancellation()
        try validate(response)
        return try saveToCache(temporaryURL: temporaryURL, for: remoteURL.absoluteString)
    }

    func downloadAndCache(url: URL) {
        if cachedURL(for: url.absoluteString) != nil { return }

        URLSession.shared.downloadTask(with: url) { [weak self] localURL, response, error in
            guard let self, let localURL, let response, error == nil else { return }
            do {
                try self.validate(response)
                try self.saveToCache(temporaryURL: localURL, for: url.absoluteString)
            } catch { return }
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
