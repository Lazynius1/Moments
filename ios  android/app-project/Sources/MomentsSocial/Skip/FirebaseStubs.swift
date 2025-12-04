// MARK: - Firebase Stubs for Skip (Android-only compilation)
// Estos tipos permiten que el código compile en Swift
// Skip transpilará las llamadas a Firebase a Kotlin usando Firebase Android SDK

import Foundation
import SwiftUI

// Stubs para tipos de Firebase que permiten compilación en Swift
// Skip transpilará estas llamadas a Firebase Android SDK

public struct FirebaseApp {
    public static func configure() {
        // Skip transpilará esto a Firebase.initializeApp() en Kotlin
    }
}

public struct Auth {
    public static func auth() -> Auth {
        return Auth()
    }
    
    public var currentUser: User? {
        return nil
    }
    
    public func addStateDidChangeListener(_ listener: @escaping (Auth, User?) -> Void) -> String {
        return ""
    }
    
    public func removeStateDidChangeListener(_ handle: String) {
    }
    
    public func signIn(withEmail email: String, password: String, completion: @escaping (AuthResult?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    public func createUser(withEmail email: String, password: String, completion: @escaping (AuthResult?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    public func signOut() throws {
        // Android: Sign out will be handled natively
    }
}

public struct User {
    public var uid: String { return "" }
    public var metadata: UserMetadata { return UserMetadata() }
}

public struct UserMetadata {
    public var creationDate: Date? { return nil }
}

public struct AuthResult {
    public var user: User { return User() }
}

public struct AuthCredential {
    // Placeholder for credentials
}

public struct AuthErrorCode: RawRepresentable, Equatable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let emailAlreadyInUse = AuthErrorCode(rawValue: 17007)
    public static let weakPassword = AuthErrorCode(rawValue: 17026)
    public static let invalidEmail = AuthErrorCode(rawValue: 17008)
    public static let wrongPassword = AuthErrorCode(rawValue: 17009)
    public static let userNotFound = AuthErrorCode(rawValue: 17011)
    public static let networkError = AuthErrorCode(rawValue: 17020)
    public static let userDisabled = AuthErrorCode(rawValue: 17005)
    public static let tooManyRequests = AuthErrorCode(rawValue: 17010)
}

public struct Firestore {
    public static func firestore() -> Firestore {
        return Firestore()
    }
    
    public var settings: FirestoreSettings {
        get { return FirestoreSettings() }
        set { /* Android: Settings will be configured natively */ }
    }
    
    public func enableNetwork() {
        // Android: Network enable will be handled natively
    }
    
    public func collectionGroup(_ collectionID: String) -> Query {
        return Query()
    }
    
    public func batch() -> WriteBatch {
        return WriteBatch()
    }
    
    public func collection(_ path: String) -> CollectionReference {
        return CollectionReference()
    }
    
    public func runTransaction(_ updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?, completion: @escaping (Any?, Error?) -> Void) {
        // Android: Transaction will be handled natively
        let transaction = Transaction()
        var error: NSError?
        let result = updateBlock(transaction, &error)
        completion(result, error)
    }
    
    // MARK: - Encoder/Decoder
    public struct Encoder {
        public init() {}
        
        public func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
            // Android: Encoding will be handled natively
            return [:]
        }
    }
    
    public struct Decoder {
        public init() {}
        
        public func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) throws -> T {
            // Android: Decoding will be handled natively
            throw NSError(domain: "FirebaseStubs", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stub implementation"])
        }
    }
}

public struct WriteBatch {
    public func setData(_ data: [String: Any], forDocument document: DocumentReference) {
        // Android: Batch setData will be handled natively
    }
    
    public func updateData(_ data: [String: Any], forDocument document: DocumentReference) {
        // Android: Batch updateData will be handled natively
    }
    
    public func deleteDocument(_ document: DocumentReference) {
        // Android: Batch deleteDocument will be handled natively
    }
    
    public func commit(completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    public func commit() async throws {
        // Android: Batch commit will be handled natively
    }
}

public struct Transaction {
    public func getDocument(_ document: DocumentReference) throws -> DocumentSnapshot {
        return DocumentSnapshot()
    }
    
    public func setData(_ data: [String: Any], forDocument document: DocumentReference) {
        // Android: Transaction setData will be handled natively
    }
    
    public func updateData(_ data: [String: Any], forDocument document: DocumentReference) {
        // Android: Transaction updateData will be handled natively
    }
    
    public func deleteDocument(_ document: DocumentReference) {
        // Android: Transaction deleteDocument will be handled natively
    }
}

public struct FirestoreSettings {
    public var cacheSettings: CacheSettings?
}

public struct PersistentCacheSettings {
    public init(sizeBytes: NSNumber) {
    }
}

public typealias CacheSettings = PersistentCacheSettings

public struct CollectionReference {
    public func document(_ path: String? = nil) -> DocumentReference {
        return DocumentReference()
    }
    
    public func addDocument(data: [String: Any]) -> DocumentReference {
        return DocumentReference()
    }
    
    public func addDocument(data: [String: Any], completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    public func collection(_ path: String) -> CollectionReference {
        return CollectionReference()
    }
    
    public func whereField(_ field: String, arrayContains: Any) -> Query {
        return Query()
    }
    
    public func whereField(_ field: String, isEqualTo: Any) -> Query {
        return Query()
    }
    
    public func whereField(_ field: String, isGreaterThan: Any) -> Query {
        return Query()
    }
    
    public func whereField(_ field: String, isGreaterThanOrEqualTo: Any) -> Query {
        return Query()
    }
    
    public func whereField(_ field: FieldPath, in: [String]) -> Query {
        return Query()
    }
    
    public func order(by: String, descending: Bool = false) -> Query {
        return Query()
    }
    
    public func getDocuments(completion: @escaping (QuerySnapshot?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    public func getDocuments() async throws -> QuerySnapshot {
        return QuerySnapshot()
    }
}

public struct DocumentReference {
    public var documentID: String { return "" }
    
    public func setData(_ data: [String: Any], completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    public func setData(_ data: [String: Any], merge: Bool, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    public func setData(_ data: [String: Any], merge: Bool) async throws {
        // Stub for async/await setData with merge
    }
    
    public func updateData(_ data: [String: Any], completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    public func updateData(_ data: [String: Any]) async throws {
        // Stub for async/await updateData
    }
    
    public func getDocument(completion: @escaping (DocumentSnapshot?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    public func getDocument() async throws -> DocumentSnapshot {
        return DocumentSnapshot()
    }
    
    public func collection(_ path: String) -> CollectionReference {
        return CollectionReference()
    }
    
    public func addSnapshotListener(_ listener: @escaping (DocumentSnapshot?, Error?) -> Void) -> ListenerRegistration {
        return ListenerRegistration()
    }
    
    public func delete(completion: @escaping (Error?) -> Void) {
        // Android: Document deletion will be handled natively
        completion(nil)
    }
}

public struct DocumentSnapshot {
    public var exists: Bool { return false }
    
    public func data() -> [String: Any]? {
        return nil
    }
    
    public func data<T: Decodable>(as type: T.Type) throws -> T {
        throw NSError(domain: "FirebaseStubs", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stub implementation"])
    }
}

public struct FieldValue {
    public static func arrayUnion(_ elements: [Any]) -> FieldValue {
        return FieldValue()
    }
    
    public static func arrayRemove(_ elements: [Any]) -> FieldValue {
        return FieldValue()
    }
    
    public static func serverTimestamp() -> FieldValue {
        return FieldValue()
    }
    
    public static func delete() -> FieldValue {
        return FieldValue()
    }
    
    public static func increment(_ value: Int64) -> FieldValue {
        return FieldValue()
    }
}

public struct FieldPath {
    public static func documentID() -> FieldPath {
        return FieldPath()
    }
    
    private init() {}
}

public struct Query {
    public func whereField(_ field: String, isEqualTo: Any) -> Query {
        return Query()
    }
    
    public func whereField(_ field: FieldPath, in: [String]) -> Query {
        return Query()
    }
    
    public func whereField(_ field: String, arrayContains: Any) -> Query {
        return Query()
    }
    
    public func whereField(_ field: String, isGreaterThan: Any) -> Query {
        return Query()
    }
    
    public func whereField(_ field: String, isGreaterThanOrEqualTo: Any) -> Query {
        return Query()
    }
    
    public func order(by: String, descending: Bool = false) -> Query {
        return Query()
    }
    
    public func getDocuments(completion: @escaping (QuerySnapshot?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    public func getDocuments() async throws -> QuerySnapshot {
        return QuerySnapshot()
    }
    
    public func addSnapshotListener(_ listener: @escaping (QuerySnapshot?, Error?) -> Void) -> ListenerRegistration {
        return ListenerRegistration()
    }
    
    public func limit(to count: Int) -> Query {
        return Query()
    }
    
    public func start(afterDocument document: QueryDocumentSnapshot) -> Query {
        return Query()
    }
}

public struct QuerySnapshot {
    public var documents: [QueryDocumentSnapshot] { return [] }
}

public struct QueryDocumentSnapshot {
    public var documentID: String { return "" }
    
    public func data() -> [String: Any] {
        return [:]
    }
    
    public func data<T: Decodable>(as type: T.Type) throws -> T {
        throw NSError(domain: "FirebaseStubs", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stub implementation"])
    }
    
    public var reference: DocumentReference {
        return DocumentReference()
    }
}

public typealias AuthStateDidChangeListenerHandle = String

public struct ListenerRegistration {
    public func remove() {
    }
}

// MARK: - Firebase Messaging Stubs
public class Messaging {
    public static func messaging() -> Messaging {
        return Messaging()
    }
    
    public var delegate: MessagingDelegate? = nil
    
    public var apnsToken: Data? = nil
    
    public func token(completion: @escaping (String?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    private init() {}
}

public protocol MessagingDelegate: AnyObject {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?)
}

// MARK: - Firebase Timestamp Stub
public struct Timestamp: Codable {
    public let seconds: Int64
    public let nanoseconds: Int32
    
    public init(seconds: Int64 = 0, nanoseconds: Int32 = 0) {
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }
    
    public init(date: Date) {
        let timeInterval = date.timeIntervalSince1970
        self.seconds = Int64(timeInterval)
        self.nanoseconds = Int32((timeInterval - Double(Int64(timeInterval))) * 1_000_000_000)
    }
    
    public func dateValue() -> Date {
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1_000_000_000)
    }
}

// MARK: - Firebase Storage Stubs
public struct FirebaseStorage {
    public struct Storage {
        public static func storage() -> Storage {
            return Storage()
        }
        
        public func reference() -> StorageReference {
            return StorageReference()
        }
    }
}

public struct StorageReference {
    public func child(_ path: String) -> StorageReference {
        return StorageReference()
    }
    
    public func putData(_ data: Data, metadata: StorageMetadata?, completion: @escaping (StorageMetadata?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    public func downloadURL(completion: @escaping (URL?, Error?) -> Void) {
        completion(nil, nil)
    }
}

public struct StorageMetadata {
    public var contentType: String = ""
}
