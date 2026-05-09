import Foundation
import AuthenticationServices
import FirebaseAuth

class PasskeyService: NSObject, ObservableObject {
    static let shared = PasskeyService()

    // Configuración
    private let relyingPartyIdentifier = "momentsapp.app"
    private let baseURL = "https://europe-southwest1-glowsy-6a40e.cloudfunctions.net"

    // Callbacks guardados para cuando responda el delegado
    private var registrationCompletion: ((Result<Void, Error>) -> Void)?
    private var loginCompletion: ((Result<String, Error>) -> Void)?

    // Referencias a los challenges actuales
    private var currentRegisterChallenge: String?
    private var currentLoginChallenge: String?

    // MARK: - Red (HTTP)

    private func callFunction(name: String, payload: [String: Any]? = nil, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/\(name)") else {
            completion(.failure(NSError(domain: "PasskeyService", code: 400, userInfo: [NSLocalizedDescriptionKey: "URL inválida"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let payload = payload {
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        }

        let task = { (req: URLRequest) in
            URLSession.shared.dataTask(with: req) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(domain: "PasskeyService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Sin datos del servidor"])))
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let errorMsg = json["error"] as? String {
                            completion(.failure(NSError(domain: "PasskeyService", code: 400, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                        } else {
                            completion(.success(json))
                        }
                    } else {
                        completion(.failure(NSError(domain: "PasskeyService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Formato JSON inválido"])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }

        if let currentUser = Auth.auth().currentUser {
            currentUser.getIDToken { token, error in
                if let token = token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                task(request)
            }
        } else {
            task(request)
        }
    }

    // MARK: - Registro de Passkey

    func registerPasskey(completion: @escaping (Result<Void, Error>) -> Void) {
        guard Auth.auth().currentUser != nil else {
            completion(.failure(NSError(domain: "PasskeyService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
            return
        }

        self.registrationCompletion = completion

        callFunction(name: "passkeyRegisterChallenge") { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let data):
                guard let challengeStr = data["challenge"] as? String,
                      let challengeData = self.base64URLDecode(challengeStr) else {
                    self.registrationCompletion?(.failure(NSError(domain: "PasskeyService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Challenge inválido del servidor"])))
                    self.registrationCompletion = nil
                    return
                }

                let uidData = Auth.auth().currentUser?.uid.data(using: .utf8) ?? Data()

                self.currentRegisterChallenge = challengeStr

                DispatchQueue.main.async {
                    let username = LocalPersistenceService.shared.loadCurrentUser()?.username ?? Auth.auth().currentUser?.displayName ?? "tu cuenta"
                    self.performRegistration(challenge: challengeData, userId: uidData, userName: username)
                }

            case .failure(let error):
                self.registrationCompletion?(.failure(error))
                self.registrationCompletion = nil
            }
        }
    }

    private func performRegistration(challenge: Data, userId: Data, userName: String) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userId)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Login con Passkey

    func loginWithPasskey(completion: @escaping (Result<String, Error>) -> Void) {
        self.loginCompletion = completion

        callFunction(name: "passkeyLoginChallenge") { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let data):
                guard let challengeStr = data["challenge"] as? String,
                      let challengeData = self.base64URLDecode(challengeStr) else {
                    self.loginCompletion?(.failure(NSError(domain: "PasskeyService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Challenge inválido del servidor"])))
                    self.loginCompletion = nil
                    return
                }

                self.currentLoginChallenge = challengeStr

                DispatchQueue.main.async {
                    self.performLogin(challenge: challengeData)
                }

            case .failure(let error):
                self.loginCompletion?(.failure(error))
                self.loginCompletion = nil
            }
        }
    }

    private func performLogin(challenge: Data) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Helpers de parseo

    private func base64URLDecode(_ base64URL: String) -> Data? {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingLength = 4 - (base64.count % 4)
        if paddingLength < 4 {
            base64.append(String(repeating: "=", count: paddingLength))
        }

        return Data(base64Encoded: base64)
    }

    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension PasskeyService: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {

        // 1. Registro exitoso
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            let responsePayload: [String: Any] = [
                "id": base64URLEncode(credential.credentialID),
                "rawId": base64URLEncode(credential.credentialID),
                "type": "public-key",
                "response": [
                    "clientDataJSON": base64URLEncode(credential.rawClientDataJSON),
                    "attestationObject": base64URLEncode(credential.rawAttestationObject ?? Data())
                ]
            ]

            callFunction(name: "passkeyRegisterVerify", payload: responsePayload) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.registrationCompletion?(.success(()))
                    case .failure(let error):
                        self?.registrationCompletion?(.failure(error))
                    }
                    self?.registrationCompletion = nil
                }
            }
        }

        // 2. Login exitoso
        else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            guard let originalChallenge = currentLoginChallenge else {
                loginCompletion?(.failure(NSError(domain: "PasskeyService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No hay challenge original guardado"])))
                loginCompletion = nil
                return
            }

            let responsePayload: [String: Any] = [
                "id": base64URLEncode(credential.credentialID),
                "rawId": base64URLEncode(credential.credentialID),
                "type": "public-key",
                "originalChallenge": originalChallenge,
                "response": [
                    "clientDataJSON": base64URLEncode(credential.rawClientDataJSON),
                    "authenticatorData": base64URLEncode(credential.rawAuthenticatorData),
                    "signature": base64URLEncode(credential.signature),
                    "userHandle": credential.userID.map { base64URLEncode($0) } ?? ""
                ]
            ]

            callFunction(name: "passkeyLoginVerify", payload: responsePayload) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        if let customToken = data["customToken"] as? String {
                            self?.loginCompletion?(.success(customToken))
                        } else {
                            self?.loginCompletion?(.failure(NSError(domain: "PasskeyService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Token no recibido"])))
                        }
                    case .failure(let error):
                        self?.loginCompletion?(.failure(error))
                    }
                    self?.loginCompletion = nil
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        registrationCompletion?(.failure(error))
        loginCompletion?(.failure(error))
        registrationCompletion = nil
        loginCompletion = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension PasskeyService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}
