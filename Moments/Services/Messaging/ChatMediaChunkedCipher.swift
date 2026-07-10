import CryptoKit
import Foundation

/// Formato de fichero cifrado por bloques para media grande.
/// Cada bloque usa un nonce AES-GCM independiente y autentica su índice para
/// impedir reordenaciones. El formato legacy de un único `SealedBox` se mantiene
/// en `EncryptionService` para mensajes existentes.
enum ChatMediaChunkedCipher {
    static let metadataVersion = "2.0"
    static let algorithm = "AES.GCM.CHUNKED+HKDF-SHA256"

    private static let magic = Data([0x4D, 0x43, 0x48, 0x41, 0x54, 0x30, 0x32, 0x00]) // MCHAT02\0
    private static let defaultChunkSize = 1_048_576
    private static let maximumChunkSize = 4_194_304
    private static let sealedOverhead = 28 // nonce (12) + tag (16)

    static func encryptFile(
        inputURL: URL,
        outputURL: URL,
        key: SymmetricKey,
        authenticatedData: Data,
        chunkSize: Int = defaultChunkSize
    ) throws -> Int64 {
        guard (64 * 1024...maximumChunkSize).contains(chunkSize) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: inputURL.path)
        let plaintextSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        try prepareOutputFile(at: outputURL)

        let input = try FileHandle(forReadingFrom: inputURL)
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? input.close()
            try? output.close()
        }

        do {
            try output.write(contentsOf: magic)
            try output.write(contentsOf: encoded(UInt32(chunkSize)))
            try output.write(contentsOf: encoded(UInt64(plaintextSize)))

            var chunkIndex: UInt64 = 0
            while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                let sealed = try AES.GCM.seal(
                    chunk,
                    using: key,
                    authenticating: chunkAuthenticatedData(authenticatedData, index: chunkIndex)
                )
                guard let combined = sealed.combined,
                      combined.count <= Int(UInt32.max) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try output.write(contentsOf: encoded(UInt32(combined.count)))
                try output.write(contentsOf: combined)
                chunkIndex += 1
            }
            try output.synchronize()
            return plaintextSize
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    static func decryptFile(
        inputURL: URL,
        outputURL: URL,
        key: SymmetricKey,
        authenticatedData: Data,
        expectedPlaintextSize: Int64
    ) throws {
        try prepareOutputFile(at: outputURL)

        let input = try FileHandle(forReadingFrom: inputURL)
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? input.close()
            try? output.close()
        }

        do {
            guard try readExactly(magic.count, from: input) == magic else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let chunkSize = Int(try decodeUInt32(readExactly(4, from: input)))
            let declaredSize = Int64(bitPattern: try decodeUInt64(readExactly(8, from: input)))
            guard (64 * 1024...maximumChunkSize).contains(chunkSize),
                  declaredSize >= 0,
                  declaredSize == expectedPlaintextSize else {
                throw CocoaError(.fileReadCorruptFile)
            }

            var written: Int64 = 0
            var chunkIndex: UInt64 = 0
            while true {
                let lengthData = try input.read(upToCount: 4) ?? Data()
                if lengthData.isEmpty { break }
                guard lengthData.count == 4 else { throw CocoaError(.fileReadCorruptFile) }

                let sealedLength = Int(try decodeUInt32(lengthData))
                guard sealedLength >= sealedOverhead,
                      sealedLength <= chunkSize + sealedOverhead else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                let sealedData = try readExactly(sealedLength, from: input)
                let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
                let plaintext = try AES.GCM.open(
                    sealedBox,
                    using: key,
                    authenticating: chunkAuthenticatedData(authenticatedData, index: chunkIndex)
                )
                written += Int64(plaintext.count)
                guard written <= expectedPlaintextSize else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try output.write(contentsOf: plaintext)
                chunkIndex += 1
            }

            guard written == expectedPlaintextSize else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func prepareOutputFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func chunkAuthenticatedData(_ base: Data, index: UInt64) -> Data {
        var result = base
        result.append(encoded(index))
        return result
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let part = try handle.read(upToCount: count - result.count), !part.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            result.append(part)
        }
        return result
    }

    private static func encoded(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private static func encoded(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private static func decodeUInt32(_ data: Data) throws -> UInt32 {
        guard data.count == 4 else { throw CocoaError(.fileReadCorruptFile) }
        return data.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
    }

    private static func decodeUInt64(_ data: Data) throws -> UInt64 {
        guard data.count == 8 else { throw CocoaError(.fileReadCorruptFile) }
        return data.reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    }
}
