# 📦 Análisis de Dependencias: Migración Glowsy → Skip

## 🔍 Dependencias Actuales de Glowsy

### Firebase Suite ✅/⚠️
| Librería | iOS | Android | Estrategia |
|----------|-----|---------|------------|
| FirebaseCore | ✅ | ✅ | SDK nativo Android |
| FirebaseAuth | ✅ | ✅ | SDK nativo Android |
| FirebaseFirestore | ✅ | ✅ | SDK nativo Android |
| FirebaseStorage | ✅ | ✅ | SDK nativo Android |
| FirebaseMessaging | ✅ | ✅ | SDK nativo Android |
| FirebaseVertexAI | ✅ | ✅ | SDK nativo Android |

**Acción Requerida:** Crear wrappers abstractos que usen SDKs nativos en cada plataforma.

---

### Image Loading ❌→✅
| Librería | iOS | Android | Estrategia |
|----------|-----|---------|------------|
| Kingfisher | ✅ | ❌ | Reemplazar con Coil (Android) |

**Uso Identificado:**
- `KFImage` en múltiples vistas (StoryModels, FeedView, ProfileView)
- Caching de imágenes con Kingfisher
- Placeholders y animaciones

**Archivos Afectados:**
- `Glowsy/Views/story/StoryModels.swift` (múltiples usos)
- `Glowsy/Services/CacheManager.swift`
- `Glowsy/GlowsyApp.swift` (configuración de cache)

**Estrategia de Migración:**
```swift
// Crear wrapper abstracto
protocol ImageLoader {
    func loadImage(from url: URL) -> Image
    func preloadImage(from url: URL) async
}

#if !SKIP
import Kingfisher
class KingfisherImageLoader: ImageLoader {
    // Implementación actual
}
#endif

#if SKIP
import coil3 // Coil para Android
class CoilImageLoader: ImageLoader {
    // Implementación Android
}
#endif

// Uso en vistas
struct CompatibleImage: View {
    let url: URL
    var body: some View {
        ImageLoaderFactory.shared.loader.loadImage(from: url)
    }
}
```

**Estimación:** 5-7 días

---

### Ads ❌→✅
| Librería | iOS | Android | Estrategia |
|----------|-----|---------|------------|
| GoogleMobileAds | ✅ | ✅ | SDK nativo Android |

**Uso Identificado:**
- `Glowsy/ad/` - Toda la carpeta de anuncios
- FeedNativeAd, StoryNativeAd
- AdMob Configuration

**Estrategia:**
- Crear abstracciones para Ads
- Usar SDK nativo de cada plataforma
- Mantener misma API en ambos lados

**Estimación:** 10-15 días

---

### Image Cropping ❌→✅
| Librería | iOS | Android | Estrategia |
|----------|-----|---------|------------|
| TOCropViewController | ✅ | ❌ | Reemplazar con CropImage (AndroidX) |

**Uso Identificado:**
- `Glowsy/Views/Profile/PhotoCropEditorView.swift`
- Editor de historias (cropping de imágenes)

**Estrategia:**
```swift
protocol ImageCropper {
    func crop(image: UIImage, completion: @escaping (UIImage?) -> Void)
}

#if !SKIP
import TOCropViewController
// Implementación iOS
#endif

#if SKIP
import androidx.activity.result.contract.ActivityResultContracts
// Implementación Android con CropImage
#endif
```

**Estimación:** 3-5 días

---

### Utilidades ✅
| Librería | iOS | Android | Estrategia |
|----------|-----|---------|------------|
| ZIPFoundation | ✅ | ✅ | Skip compatible |
| Combine | ✅ | ✅ | Skip compatible (async/await) |

**No requiere cambios**

---

## 🔧 Dependencias del Sistema

### UIKit ❌→✅
**Problema:** UIKit es iOS-only
**Uso Identificado:**
- `UIApplication` lifecycle
- `UIImageView` en algunos componentes
- `PHImageManager` para galería
- `UIViewRepresentable` para componentes nativos

**Estrategia:**
```swift
// Abstraer funcionalidades específicas
#if !SKIP
import UIKit
typealias PlatformImage = UIImage
typealias PlatformImageView = UIImageView
#endif

#if SKIP
import android.graphics.Bitmap
typealias PlatformImage = Bitmap
typealias PlatformImageView = ImageView
#endif
```

**Estimación:** Variable (según uso específico)

---

### PhotoKit ❌→✅
**Problema:** PhotoKit es iOS-only
**Uso Identificado:**
- `Glowsy/Views/Creator/CreatorView.swift` - Acceso a galería
- `PHAsset`, `PHImageManager`

**Estrategia:**
```swift
#if !SKIP
import Photos
class PhotoLibraryService {
    func fetchAssets() -> [PHAsset] { }
}
#endif

#if SKIP
import android.provider.MediaStore
class PhotoLibraryService {
    func fetchAssets() -> [MediaStoreAsset] { }
}
#endif
```

**Estimación:** 8-12 días

---

### CoreLocation ✅
**Estado:** Skip compatible (pero requiere permisos específicos)

**Uso Identificado:**
- `Glowsy/Models/Models.swift` - Ubicación en momentos

**No requiere cambios mayores**

---

## 📋 Plan de Reemplazo por Categoría

### Categoría 1: Firebase (Alta Prioridad)
**Esfuerzo:** Alto
**Riesgo:** Medio
**Timeline:** 15-20 días

**Acciones:**
1. Crear protocolos abstractos
2. Implementar wrappers iOS
3. Implementar wrappers Android
4. Migrar servicios uno por uno
5. Testing exhaustivo

---

### Categoría 2: Image Loading (Alta Prioridad)
**Esfuerzo:** Medio
**Riesgo:** Bajo
**Timeline:** 5-7 días

**Acciones:**
1. Crear `ImageLoader` protocol
2. Implementar `KingfisherImageLoader` (iOS)
3. Implementar `CoilImageLoader` (Android)
4. Crear `CompatibleImage` view wrapper
5. Reemplazar todos los `KFImage` usages
6. Testing visual en ambas plataformas

---

### Categoría 3: Ads (Media Prioridad)
**Esfuerzo:** Medio-Alto
**Riesgo:** Medio
**Timeline:** 10-15 días

**Acciones:**
1. Abstraer configuración de Ads
2. Implementar iOS con GoogleMobileAds
3. Implementar Android con Google Mobile Ads SDK
4. Migrar componentes de anuncios
5. Testing de monetización

---

### Categoría 4: Native Components (Baja Prioridad Inicial)
**Esfuerzo:** Variable
**Riesgo:** Alto
**Timeline:** Según necesidad

**Acciones:**
- Cropping: 3-5 días
- Photo Library: 8-12 días
- Camera: 10-15 días
- Otros nativos: Según caso

---

## 🎯 Orden Recomendado de Migración

### Fase 1: Foundation (Semana 1-2)
1. ✅ Firebase Core y Auth
2. ✅ Modelos básicos
3. ✅ Firestore básico

### Fase 2: Core Features (Semana 3-4)
1. ✅ Image Loading (Kingfisher → Coil)
2. ✅ Vistas básicas
3. ✅ Navegación

### Fase 3: Advanced Features (Semana 5-8)
1. ✅ Ads integration
2. ✅ Storage completo
3. ✅ Notificaciones

### Fase 4: Native Features (Semana 9-12)
1. ✅ Photo Library
2. ✅ Camera
3. ✅ Image Cropping
4. ✅ Otros nativos

---

## 📊 Resumen de Estimaciones

| Categoría | Días | Complejidad | Prioridad |
|-----------|------|-------------|-----------|
| Firebase | 15-20 | ⭐⭐⭐⭐⭐ | 🔴 Alta |
| Image Loading | 5-7 | ⭐⭐⭐ | 🔴 Alta |
| Ads | 10-15 | ⭐⭐⭐⭐ | 🟡 Media |
| Photo Library | 8-12 | ⭐⭐⭐⭐ | 🟢 Baja |
| Cropping | 3-5 | ⭐⭐ | 🟢 Baja |
| Otros Nativos | 10-20 | ⭐⭐⭐⭐ | 🟢 Baja |
| **TOTAL** | **51-79 días** | | |

---

## ✅ Checklist de Verificación

Para cada dependencia:

- [ ] ¿Existe equivalente Android?
- [ ] ¿Se puede abstraer con protocolos?
- [ ] ¿Skip lo transpila directamente?
- [ ] ¿Requiere wrapper custom?
- [ ] ¿Testing plan definido?

---

**Última actualización:** $(date)


