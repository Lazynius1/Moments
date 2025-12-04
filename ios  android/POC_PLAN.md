# 🚀 Plan de PoC: Migración Glowsy a Skip

## 🎯 Objetivo
Crear un Proof of Concept funcional que demuestre que es posible migrar Glowsy a Skip con Firebase funcionando correctamente.

---

## 📋 Scope del PoC

### Features a Migrar:
1. ✅ **Autenticación Básica**
   - Login con email/password
   - Registro simple
   - Estado de autenticación

2. ✅ **Vista de Perfil Básica**
   - Mostrar datos del usuario
   - Avatar
   - Bio básica

3. ✅ **Firestore Integration**
   - Leer datos de usuario
   - Escribir datos simples

---

## 🛠️ Pasos Técnicos

### Paso 1: Setup del Proyecto Skip Base

#### 1.1 Limpiar proyecto ejemplo
```bash
cd "ios  android/app-project"
# Mantener solo estructura base
```

#### 1.2 Configurar Package.swift
```swift
// Agregar dependencias necesarias
dependencies: [
    .package(url: "https://source.skip.tools/skip.git", from: "1.6.27"),
    .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
    // Nota: Firebase se agregará manualmente para Android
]
```

#### 1.3 Configurar Firebase para Android
- Agregar `google-services.json` en `Android/app/`
- Configurar `build.gradle.kts` con Firebase
- Configurar `AndroidManifest.xml`

---

### Paso 2: Crear Abstracción Firebase

#### 2.1 Protocolo de Autenticación
```swift
// Sources/MomentsSocial/Services/AuthProtocol.swift
protocol AuthServiceProtocol {
    func signIn(email: String, password: String) async throws -> User
    func signUp(email: String, password: String) async throws -> User
    func signOut() throws
    var currentUser: User? { get }
}
```

#### 2.2 Implementación iOS
```swift
#if !SKIP
import FirebaseAuth

class FirebaseAuthService: AuthServiceProtocol {
    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }
    // ...
}
#endif
```

#### 2.3 Implementación Android
```swift
#if SKIP
import android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth

class FirebaseAuthService: AuthServiceProtocol {
    private let auth = FirebaseAuth.getInstance()
    
    func signIn(email: String, password: String) async throws -> User {
        let task = auth.signInWithEmailAndPassword(email, password)
        let result = try await Tasks.await(task)
        return result.user
    }
    // ...
}
#endif
```

---

### Paso 3: Migrar Modelo User

#### 3.1 Copiar AppUser
```swift
// Sources/MomentsSocial/Models/AppUser.swift
// Copiar de Glowsy/Models/User.swift
// Adaptar para Skip:
// - Cambiar Timestamp decoding para ambas plataformas
// - Verificar todos los tipos son compatibles
```

#### 3.2 Tests
- Verificar que AppUser se puede codificar/decodificar
- Verificar que funciona en ambas plataformas

---

### Paso 4: Crear Vista de Login

#### 4.1 LoginView Simple
```swift
// Sources/MomentsSocial/Views/LoginView.swift
struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @StateObject private var authService: AuthService
    
    var body: some View {
        VStack {
            TextField("Email", text: $email)
            SecureField("Password", text: $password)
            Button("Login") {
                Task {
                    try? await authService.signIn(email: email, password: password)
                }
            }
        }
    }
}
```

---

### Paso 5: Crear Vista de Perfil

#### 5.1 ProfileView Simple
```swift
// Sources/MomentsSocial/Views/ProfileView.swift
struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    
    var body: some View {
        VStack {
            // Avatar
            // Username
            // Bio
        }
        .task {
            await viewModel.loadUser()
        }
    }
}
```

#### 5.2 ProfileViewModel
```swift
@Observable
class ProfileViewModel {
    var user: AppUser?
    var isLoading = false
    
    func loadUser() async {
        // Usar FirestoreService para cargar usuario
    }
}
```

---

### Paso 6: Integrar con Firestore

#### 6.1 FirestoreService Wrapper
```swift
protocol FirestoreServiceProtocol {
    func getUser(userId: String) async throws -> AppUser?
    func updateUser(userId: String, data: [String: Any]) async throws
}

#if !SKIP
// Implementación iOS
#endif

#if SKIP
// Implementación Android
#endif
```

---

## ✅ Checklist del PoC

### Setup
- [ ] Proyecto Skip compilando correctamente
- [ ] Firebase configurado en Android
- [ ] Firebase configurado en iOS
- [ ] Builds funcionando en ambas plataformas

### Modelos
- [ ] AppUser migrado y funcionando
- [ ] Codificación/Decodificación funciona
- [ ] Compatible con ambas plataformas

### Autenticación
- [ ] Login funciona en iOS
- [ ] Login funciona en Android
- [ ] Registro funciona en ambas plataformas
- [ ] Estado de autenticación persiste

### Firestore
- [ ] Lectura de datos funciona en iOS
- [ ] Lectura de datos funciona en Android
- [ ] Escritura de datos funciona en ambas

### UI
- [ ] LoginView se ve bien en iOS
- [ ] LoginView se ve bien en Android
- [ ] ProfileView se ve bien en ambas plataformas
- [ ] Navegación funciona

### Testing
- [ ] Tests unitarios pasando
- [ ] Tests de integración Firebase pasando
- [ ] No crashes en ninguna plataforma

---

## 🐛 Problemas Conocidos a Resolver

### 1. Firebase Timestamp
**Problema:** iOS usa `Timestamp`, Android usa `com.google.firebase.Timestamp`
**Solución:** Crear wrapper que convierta entre ambos

### 2. Async/Await
**Problema:** Diferentes implementaciones entre plataformas
**Solución:** Usar Task/async-await estándar de Swift (Skip lo transpila)

### 3. Image Loading
**Problema:** Kingfisher no funciona en Android
**Solución:** Para PoC, usar AsyncImage nativo. Para producción, usar Coil.

### 4. Navigation
**Problema:** NavigationStack puede tener diferencias
**Solución:** Usar NavigationStack estándar (compatible con Skip)

---

## 📊 Criterios de Éxito

El PoC se considera exitoso si:

1. ✅ **Login funciona** en ambas plataformas
2. ✅ **Firestore funciona** (leer/escribir)
3. ✅ **UI se ve correctamente** en ambas plataformas
4. ✅ **No hay crashes** críticos
5. ✅ **Build time** es razonable (< 5 min)

Si el PoC es exitoso → Proceder con migración completa
Si el PoC falla → Evaluar alternativas o ajustar estrategia

---

## ⏱️ Timeline Estimado

- **Día 1-2**: Setup proyecto y Firebase
- **Día 3-4**: Abstracciones Firebase
- **Día 5-6**: Migración modelos
- **Día 7-8**: Views básicas
- **Día 9-10**: Testing y debugging
- **Total: 10 días** (2 semanas con buffer)

---

## 📝 Notas de Desarrollo

### Comandos Útiles:
```bash
# Verificar proyecto Skip
skip verify

# Build iOS
xcodebuild -workspace Project.xcworkspace -scheme "MomentsSocial App"

# Build Android
cd Android && ./gradlew build

# Ver logs Android
adb logcat | grep MomentsSocial
```

### Debugging:
- **iOS**: Usar Xcode console
- **Android**: Usar Android Studio Logcat o `adb logcat`
- **Skip Errors**: Revisar transpilación en build logs

---

## 🎯 Próximos Pasos Post-PoC

Si PoC es exitoso:

1. Expandir a más features (Feed, Stories)
2. Migrar servicios completos
3. Agregar integraciones nativas (Ads, etc.)
4. Optimización y pulido

---

**Creado:** $(date)
**Estado:** Pendiente de inicio


