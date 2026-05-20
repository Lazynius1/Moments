import Foundation
import CryptoKit
import CommonCrypto

enum ChatRecoveryCrypto {
    static func randomSalt(length: Int = 32) -> Data {
        Data((0..<length).map { _ in UInt8.random(in: 0...UInt8.max) })
    }

    static func derivePINKey(
        pin: String,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) throws -> SymmetricKey {
        guard let pinData = pin.data(using: .utf8) else {
            throw EncryptionError.invalidInput
        }

        var derivedKey = Data(count: keyLength)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                pinData.withUnsafeBytes { pinBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinBytes.bindMemory(to: Int8.self).baseAddress,
                        pinData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw EncryptionError.encryptionFailed
        }

        return SymmetricKey(data: derivedKey)
    }
}

extension AES.GCM.Nonce {
    var dataRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}
