import Foundation
import CryptoKit
import CommonCrypto
import Security

enum ChatRecoveryCrypto {
    static func randomSalt(length: Int = 32) -> Data {
        Data((0..<length).map { _ in UInt8.random(in: 0...UInt8.max) })
    }

    static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }
        return Data((0..<count).map { _ in UInt8.random(in: 0...UInt8.max) })
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

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecoded(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

extension AES.GCM.Nonce {
    var dataRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}
