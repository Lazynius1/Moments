import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseCore

class BestFriendsService {
    private let db = Firestore.firestore()
    private let firestoreService: FirestoreService
    private let functionsRegion = "europe-southwest1"
    private let bestFriendsOptOutFunctionName = "optOutBestFriends"

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
    
    /// Permite que el usuario actual se salga de la lista de mejores amigos de otro usuario.
    /// Esto se realiza vía Cloud Function autenticada para no abrir permisos de escritura cruzada en reglas.
    func optOutFromBestFriends(of ownerId: String, completion: @escaping (Error?) -> Void) {
        guard !ownerId.isEmpty else {
            completion(NSError(domain: "BestFriendsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "ownerId vacío"]))
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            completion(NSError(domain: "BestFriendsService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }
        
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://\(functionsRegion)-\(projectID).cloudfunctions.net/\(bestFriendsOptOutFunctionName)") else {
            completion(NSError(domain: "BestFriendsService", code: -3, userInfo: [NSLocalizedDescriptionKey: "No se pudo construir la URL de Cloud Function"]))
            return
        }
        
        currentUser.getIDTokenForcingRefresh(false) { token, tokenError in
            if let tokenError = tokenError {
                completion(tokenError)
                return
            }
            
            guard let token = token else {
                completion(NSError(domain: "BestFriendsService", code: -4, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener ID token"]))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["ownerId": ownerId], options: [])
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(NSError(domain: "BestFriendsService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Respuesta inválida del servidor"]))
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let serverErrorMessage: String
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorText = json["error"] as? String {
                        serverErrorMessage = errorText
                    } else {
                        serverErrorMessage = "Error del servidor (\(httpResponse.statusCode))"
                    }
                    
                    completion(NSError(domain: "BestFriendsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: serverErrorMessage]))
                    return
                }
                
                completion(nil)
            }.resume()
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
            
            for friendId in user.bestFriends {
                dispatchGroup.enter()
                self.firestoreService.fetchUser(userId: friendId) { result in
                    defer { dispatchGroup.leave() }
                    switch result {
                    case .success(let friend):
                        if friend.isActive {
                            bestFriends.append(friend)
                        }
                    case .failure:
                        // Best friends may contain stale ids if an account was deleted.
                        // Do not break the whole settings screen for a missing profile.
                        break
                    }
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                completion(.success(bestFriends))
            }
        }
    }
}
