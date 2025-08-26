import FirebaseFirestore
import FirebaseAuth

class BestFriendsService {
    private let db = Firestore.firestore()
    private let firestoreService: FirestoreService

    init(firestoreService: FirestoreService = FirestoreService()) {
        self.firestoreService = firestoreService
    }

    // Agregar un mejor amigo
    func addBestFriend(currentUserId: String, friendId: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(currentUserId)
        userRef.updateData([
            "bestFriends": FieldValue.arrayUnion([friendId])
        ]) { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    // Eliminar un mejor amigo
    func removeBestFriend(currentUserId: String, friendId: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(currentUserId)
        userRef.updateData([
            "bestFriends": FieldValue.arrayRemove([friendId])
        ]) { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }

    // Obtener lista de mejores amigos
    func fetchBestFriends(userId: String, completion: @escaping (Result<[AppUser], Error>) -> Void) {
        db.collection("users").document(userId).getDocument { (document, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let document = document, document.exists,
                  let user = try? document.data(as: AppUser.self),
                  !user.bestFriends.isEmpty else {
                completion(.success([]))
                return
            }
            
            let dispatchGroup = DispatchGroup()
            var bestFriends: [AppUser] = []
            var fetchError: Error?
            
            for friendId in user.bestFriends {
                dispatchGroup.enter()
                self.firestoreService.fetchUser(userId: friendId) { result in
                    defer { dispatchGroup.leave() }
                    switch result {
                    case .success(let friend):
                        bestFriends.append(friend)
                    case .failure(let error):
                        fetchError = error
                    }
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                if let error = fetchError {
                    completion(.failure(error))
                } else {
                    completion(.success(bestFriends))
                }
            }
        }
    }
}
