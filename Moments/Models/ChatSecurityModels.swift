import Foundation
import FirebaseFirestore

struct ChatIdentityRecord: Codable, Hashable {
    let keyId: String
    let publicKeyBase64: String
    let algorithm: String
    let updatedAt: Date?

    init(
        keyId: String,
        publicKeyBase64: String,
        algorithm: String = "curve25519",
        updatedAt: Date? = nil
    ) {
        self.keyId = keyId
        self.publicKeyBase64 = publicKeyBase64
        self.algorithm = algorithm
        self.updatedAt = updatedAt
    }

    init?(map: [String: Any]) {
        guard
            let keyId = map["keyId"] as? String,
            let publicKeyBase64 = map["publicKeyBase64"] as? String
        else {
            return nil
        }

        self.keyId = keyId
        self.publicKeyBase64 = publicKeyBase64
        self.algorithm = map["algorithm"] as? String ?? "curve25519"

        if let timestamp = map["updatedAt"] as? Timestamp {
            self.updatedAt = timestamp.dateValue()
        } else {
            self.updatedAt = map["updatedAt"] as? Date
        }
    }

    func asFirestoreData() -> [String: Any] {
        [
            "keyId": keyId,
            "publicKeyBase64": publicKeyBase64,
            "algorithm": algorithm,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
}

struct ChatRecoveryKDFParams: Codable, Hashable {
    let iterations: Int
    let keyLength: Int
    let hash: String

    init(iterations: Int = 200_000, keyLength: Int = 32, hash: String = "SHA256") {
        self.iterations = iterations
        self.keyLength = keyLength
        self.hash = hash
    }

    init?(map: [String: Any]) {
        guard
            let iterations = map["iterations"] as? Int,
            let keyLength = map["keyLength"] as? Int,
            let hash = map["hash"] as? String
        else {
            return nil
        }

        self.iterations = iterations
        self.keyLength = keyLength
        self.hash = hash
    }

    func asFirestoreData() -> [String: Any] {
        [
            "iterations": iterations,
            "keyLength": keyLength,
            "hash": hash
        ]
    }
}

struct ChatRecoveryBundle: Codable, Hashable {
    let keyId: String?
    let encryptedPrivateKey: String
    let nonce: String
    let salt: String
    let kdf: String
    let kdfParams: ChatRecoveryKDFParams
    let keyVersion: Int
    let encryptedUserKey: String?
    let createdAt: Date?
    let updatedAt: Date?

    init(
        keyId: String? = nil,
        encryptedPrivateKey: String,
        nonce: String,
        salt: String,
        kdf: String = "PBKDF2",
        kdfParams: ChatRecoveryKDFParams = ChatRecoveryKDFParams(),
        keyVersion: Int = 1,
        encryptedUserKey: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.keyId = keyId
        self.encryptedPrivateKey = encryptedPrivateKey
        self.nonce = nonce
        self.salt = salt
        self.kdf = kdf
        self.kdfParams = kdfParams
        self.keyVersion = keyVersion
        self.encryptedUserKey = encryptedUserKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init?(map: [String: Any]) {
        guard
            let encryptedPrivateKey = map["encryptedPrivateKey"] as? String,
            let nonce = map["nonce"] as? String,
            let salt = map["salt"] as? String,
            let kdf = map["kdf"] as? String,
            let kdfParamsMap = map["kdfParams"] as? [String: Any],
            let kdfParams = ChatRecoveryKDFParams(map: kdfParamsMap),
            let keyVersion = map["keyVersion"] as? Int
        else {
            return nil
        }

        self.keyId = map["keyId"] as? String
        self.encryptedPrivateKey = encryptedPrivateKey
        self.nonce = nonce
        self.salt = salt
        self.kdf = kdf
        self.kdfParams = kdfParams
        self.keyVersion = keyVersion
        self.encryptedUserKey = map["encryptedUserKey"] as? String

        if let created = map["createdAt"] as? Timestamp {
            self.createdAt = created.dateValue()
        } else {
            self.createdAt = map["createdAt"] as? Date
        }

        if let updated = map["updatedAt"] as? Timestamp {
            self.updatedAt = updated.dateValue()
        } else {
            self.updatedAt = map["updatedAt"] as? Date
        }
    }

    func asFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "encryptedPrivateKey": encryptedPrivateKey,
            "nonce": nonce,
            "salt": salt,
            "kdf": kdf,
            "kdfParams": kdfParams.asFirestoreData(),
            "keyVersion": keyVersion,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let keyId {
            data["keyId"] = keyId
        }

        if let encryptedUserKey {
            data["encryptedUserKey"] = encryptedUserKey
        }

        if let createdAt {
            data["createdAt"] = Timestamp(date: createdAt)
        } else {
            data["createdAt"] = FieldValue.serverTimestamp()
        }

        return data
    }
}

struct ChatRecoveryAttemptState: Hashable {
    let failedAttempts: Int
    let maxAttempts: Int
    let lockedUntil: Date?

    init(
        failedAttempts: Int = 0,
        maxAttempts: Int = 5,
        lockedUntil: Date? = nil
    ) {
        self.failedAttempts = failedAttempts
        self.maxAttempts = maxAttempts
        self.lockedUntil = lockedUntil
    }

    var isLocked: Bool {
        guard let lockedUntil else { return false }
        return lockedUntil.timeIntervalSinceNow > 0
    }

    var remainingLockout: TimeInterval {
        guard let lockedUntil else { return 0 }
        return max(0, lockedUntil.timeIntervalSinceNow)
    }

    var remainingLockoutInterval: TimeInterval? {
        isLocked ? remainingLockout : nil
    }

    var remainingAttempts: Int {
        max(0, maxAttempts - failedAttempts)
    }
}

struct WrappedConversationKey: Codable, Hashable {
    let wrappedKey: String
    let senderPublicKey: String
    let recipientKeyId: String
    let wrappedAt: Date?
    let wrappedBy: String

    init(
        wrappedKey: String,
        senderPublicKey: String,
        recipientKeyId: String,
        wrappedAt: Date? = nil,
        wrappedBy: String
    ) {
        self.wrappedKey = wrappedKey
        self.senderPublicKey = senderPublicKey
        self.recipientKeyId = recipientKeyId
        self.wrappedAt = wrappedAt
        self.wrappedBy = wrappedBy
    }

    init?(map: [String: Any]) {
        guard
            let wrappedKey = map["wrappedKey"] as? String,
            let senderPublicKey = map["senderPublicKey"] as? String,
            let recipientKeyId = map["recipientKeyId"] as? String,
            let wrappedBy = map["wrappedBy"] as? String
        else {
            return nil
        }

        self.wrappedKey = wrappedKey
        self.senderPublicKey = senderPublicKey
        self.recipientKeyId = recipientKeyId
        self.wrappedBy = wrappedBy

        if let wrappedAt = map["wrappedAt"] as? Timestamp {
            self.wrappedAt = wrappedAt.dateValue()
        } else {
            self.wrappedAt = map["wrappedAt"] as? Date
        }
    }

    func asFirestoreData() -> [String: Any] {
        [
            "wrappedKey": wrappedKey,
            "senderPublicKey": senderPublicKey,
            "recipientKeyId": recipientKeyId,
            "wrappedAt": FieldValue.serverTimestamp(),
            "wrappedBy": wrappedBy
        ]
    }
}

enum ChatAccessState: Equatable {
    case available
    case needsPinSetup
    case needsRestore
    case unavailable(String)
}

struct ChatRecoveryMigrationSession: Hashable {
    let migrationId: String
    let qrPayload: String
    let expiresAt: Date
}

struct ChatRecoveryMigrationPayload: Codable, Hashable {
    let v: Int
    let uid: String
    let keyId: String
    let privateKey: String
    let userKey: String?

    init(v: Int = 1, uid: String, keyId: String, privateKey: String, userKey: String? = nil) {
        self.v = v
        self.uid = uid
        self.keyId = keyId
        self.privateKey = privateKey
        self.userKey = userKey
    }
}
