import SwiftUI
import StoreKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - Support Moments Section SIMPLIFICADA
struct SupportMomentsSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @Binding var isShowingSupportMoments: Bool
    
    var body: some View {
        Section(NSLocalizedString("support.section.title", comment: "Support Moments")) {
            // Badges de apoyo (principal)
            SettingsRow(
                icon: "star.circle",
                title: NSLocalizedString("support.badges.title", comment: "Support Badges"),
                subtitle: getBadgeSubtitle(),
                action: {
                    isShowingSupportMoments = true
                }
            )
            
            // Gestionar suscripción (solo si es Plus)
            if authService.currentUser?.isPlusSubscriber == true {
                SettingsRow(
                    icon: "creditcard.circle",
                    title: NSLocalizedString("support.manageSubscription.title", comment: "Manage Subscription"),
                    subtitle: NSLocalizedString("support.manageSubscription.subtitle", comment: "Configure your Plus subscription"),
                    action: {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    },
                    isExternal: true
                )
            }
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
    
    private func getBadgeSubtitle() -> String {
        guard let currentUser = authService.currentUser else {
            return NSLocalizedString("support.badges.subtitle.default", comment: "Unique Badges + Plus Subscription")
        }
        
        let badgeCount = currentUser.ownedBadges.count
        
        if currentUser.isPlusSubscriber && badgeCount > 0 {
            return String(format: NSLocalizedString("support.badges.subtitle.badgesAndPlus", comment: "Plus + %d badges"), badgeCount)
        } else if currentUser.isPlusSubscriber {
            return NSLocalizedString("support.badges.subtitle.plusEnabled", comment: "Plus Active - Explore available badges")
        } else if badgeCount > 0 {
            return String(format: NSLocalizedString("support.badges.subtitle.badgesOnly", comment: "%d badges + Plus Subscription"), badgeCount)
        } else {
            return NSLocalizedString("support.badges.subtitle.default", comment: "Unique Badges + Plus Subscription")
        }
    }
}

// MARK: - Support Moments View (ARREGLADO con estados correctos)
struct SupportMomentsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService
    @StateObject private var storeManager = StoreManager()
    @State private var selectedBadge: Badge? = nil
    @State private var showPurchaseConfirmation = false
    @State private var showThankYou = false
    
    var body: some View {
        SettingsSubsectionWrapper(title: NSLocalizedString("support.view.title", comment: "Support Moments")) {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Sin anuncios section
                    noAdsSection
                    
                    // Badges section
                    badgesSection
                    
                    // FAQ section
                    faqSection
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .onAppear {
                storeManager.loadProducts()
            }
            .sheet(item: $selectedBadge) { badge in
                BadgePurchaseView(badge: badge, storeManager: storeManager)
            }
            .alert(NSLocalizedString("support.view.thanks.title", comment: "¡Gracias!"), isPresented: $showThankYou) {
                Button(NSLocalizedString("settings.ok", comment: "OK")) {}
            } message: {
                Text(NSLocalizedString("support.view.thanks.message", comment: "Tu apoyo nos ayuda a mantener Moments gratuito para todos."))
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Logo de Moments
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "00A896"), Color(hex: "02C39A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                
                Text("M")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("support.view.title", comment: "Apoya Moments"))
                    .font(.custom("Poppins-Bold", size: 24))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("support.view.header.subtitle", comment: "Ayúdanos a mantener la app gratuita para todos"))
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var noAdsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("support.view.plus.title", comment: "Moments Plus"))
                    .font(.custom("Poppins-Bold", size: 20))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                // ✅ NUEVO: Mostrar estado basado en suscripción
                if authService.currentUser?.isPlusSubscriber == true {
                    // Usuario ya es Plus - mostrar badge de "ACTIVO"
                    ZStack {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(height: 24)
                        
                        Text(NSLocalizedString("support.view.plus.active", comment: "ACTIVO"))
                            .font(.custom("Poppins-Bold", size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                    }
                } else {
                    // Usuario no Plus - mostrar "POPULAR"
                    ZStack {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(height: 24)
                        
                        Text(NSLocalizedString("support.view.plus.popular", comment: "POPULAR"))
                            .font(.custom("Poppins-Bold", size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "nosign", title: NSLocalizedString("support.view.features.noAds.title", comment: "Sin anuncios"), description: NSLocalizedString("support.view.features.noAds.description", comment: "Experiencia completamente limpia"))
                FeatureRow(icon: "crown.fill", title: NSLocalizedString("support.view.features.crown.title", comment: "Badge exclusivo"), description: NSLocalizedString("support.view.features.crown.description", comment: "Muestra tu apoyo al proyecto"))
                FeatureRow(icon: "heart.fill", title: NSLocalizedString("support.view.features.development.title", comment: "Apoya el desarrollo"), description: NSLocalizedString("support.view.features.development.description", comment: "Mantiene la app gratuita para todos"))
            }
            
            // ✅ NUEVO: Botón dinámico basado en estado
            if authService.currentUser?.isPlusSubscriber == true {
                // Usuario ya es Plus - mostrar estado activo
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("support.view.plus.alreadyActive.title", comment: "¡Ya eres Moments Plus!"))
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Text(NSLocalizedString("support.view.plus.alreadyActive.description", comment: "Gracias por apoyar el proyecto"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Text("👑")
                            .font(.system(size: 24))
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                    
                    // Botón para gestionar suscripción
                    Button(action: {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .medium))
                            
                            Text(NSLocalizedString("support.manageSubscription.title", comment: "Gestionar suscripción"))
                                .font(.custom("Poppins-Medium", size: 16))
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            } else {
                // Usuario no Plus - mostrar botón de compra
                Button(action: {
                    purchasePlusSubscription()
                }) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16, weight: .bold))
                        
                        Text(String(format: NSLocalizedString("support.view.plus.get.button", comment: "Obtener Moments Plus - %@/mes"), "€2.99"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
        )
    }
    
    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("support.badges.title", comment: "Badges de apoyo"))
                    .font(.custom("Poppins-Bold", size: 20))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(NSLocalizedString("support.view.badges.oneTime", comment: "Una sola vez"))
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                    )
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(Badge.supportBadges) { badge in
                    // ✅ NUEVO: BadgeCard inteligente que detecta si ya tiene el badge
                    SmartBadgeCard(
                        badge: badge,
                        isOwned: authService.currentUser?.hasBadge(badge.id) ?? false
                    ) {
                        // Solo permitir compra si no lo tiene
                        if !(authService.currentUser?.hasBadge(badge.id) ?? false) {
                            selectedBadge = badge
                        }
                    }
                }
            }
        }
    }
    
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("support.view.faq.title", comment: "Preguntas frecuentes"))
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            VStack(spacing: 12) {
                FAQItem(
                    question: NSLocalizedString("support.view.faq.q1", comment: "¿Por qué badges de pago?"),
                    answer: NSLocalizedString("support.view.faq.a1", comment: "Los badges nos ayudan a mantener Moments gratuito para todos. Son opcionales y puramente para mostrar apoyo.")
                )
                
                FAQItem(
                    question: NSLocalizedString("support.view.faq.q2", comment: "¿Los badges dan ventajas?"),
                    answer: NSLocalizedString("support.view.faq.a2", comment: "No. Los badges son solo cosméticos. Creemos en mantener la experiencia justa para todos.")
                )
                
                FAQItem(
                    question: NSLocalizedString("support.view.faq.q3", comment: "¿Puedo ocultar mi badge?"),
                    answer: NSLocalizedString("support.view.faq.a3", comment: "Sí, puedes mostrar u ocultar tus badges en cualquier momento desde tu perfil.")
                )
                
                // ✅ NUEVA: FAQ para usuarios Plus
                if authService.currentUser?.isPlusSubscriber == true {
                    FAQItem(
                        question: NSLocalizedString("support.view.faq.q4", comment: "¿Cómo cancelo mi suscripción?"),
                        answer: NSLocalizedString("support.view.faq.a4", comment: "Puedes cancelar en cualquier momento desde Configuración de iOS > Tu Nombre > Suscripciones, o usando el botón 'Gestionar suscripción' arriba.")
                    )
                }
            }
        }
    }
    
    private func purchasePlusSubscription() {
        storeManager.purchaseSubscription { success in
            if success {
                // ✅ AGREGAR: Refrescar usuario inmediatamente
                authService.refreshCurrentUser()
                showThankYou = true
            }
        }
    }
}

// MARK: - Smart Badge Card (NUEVA)
struct SmartBadgeCard: View {
    let badge: Badge
    let isOwned: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Badge visual
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: badge.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 60, height: 60)
                        .opacity(isOwned ? 0.3 : 1.0) // ✅ Opacidad si ya lo tiene
                    
                    Text(badge.emoji)
                        .font(.system(size: 28))
                        .opacity(isOwned ? 0.5 : 1.0)
                    
                    // ✅ Indicador de "Ya poseído"
                    if isOwned {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .offset(x: 20, y: -20)
                    }
                }
                
                VStack(spacing: 4) {
                    Text(badge.name)
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)
                        .opacity(isOwned ? 0.6 : 1.0)
                    
                    // ✅ Precio o estado
                    if isOwned {
                    Text(NSLocalizedString("support.badgeCard.owned", comment: "POSEÍDO"))
                            .font(.custom("Poppins-Bold", size: 12))
                            .foregroundColor(.green)
                    } else {
                        Text(badge.price)
                            .font(.custom("Poppins-Bold", size: 16))
                            .foregroundColor(Color(hex: "00A896"))
                    }
                    
                    Text(badge.description)
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .opacity(isOwned ? 0.6 : 1.0)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isOwned ? Color.green.opacity(0.3) : Color.gray.opacity(0.2),
                                lineWidth: isOwned ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isOwned) // ✅ Deshabilitar si ya lo tiene
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "00A896"))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

// MARK: - FAQ Item
struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Text(answer)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Badge Purchase View
struct BadgePurchaseView: View {
    let badge: Badge
    @ObservedObject var storeManager: StoreManager
    @EnvironmentObject var authService: AuthService 
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var isPurchasing = false
    @State private var showThankYou = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()
                
                // Badge preview
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: badge.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 120, height: 120)
                            .scaleEffect(1.1)
                            .blur(radius: 20)
                            .opacity(0.5)
                        
                        Circle()
                            .fill(LinearGradient(
                                colors: badge.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 120, height: 120)
                        
                        Text(badge.emoji)
                            .font(.system(size: 60))
                    }
                    
                    VStack(spacing: 8) {
                        Text(badge.name)
                            .font(.custom("Poppins-Bold", size: 24))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(badge.description)
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Información del badge
                VStack(spacing: 16) {
                    InfoRow(title: "Precio", value: badge.price)
                    InfoRow(title: "Tipo", value: "Una sola vez")
                    InfoRow(title: "Visible en", value: "Tu perfil (opcional)")
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                )
                
                Spacer()
                
                // Botones
                VStack(spacing: 12) {
                    Button(action: {
                        purchaseBadge()
                    }) {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Comprar \(badge.price)")
                                    .font(.custom("Poppins-SemiBold", size: 18))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: badge.colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: badge.colors.first?.opacity(0.3) ?? .clear, radius: 8, x: 0, y: 4)
                    }
                    .disabled(isPurchasing)
                    
                    Button("Cancelar") {
                        dismiss()
                    }
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 24)
            .background(Color(colorScheme == .dark ? .black : .white))
            .navigationTitle("Comprar Badge")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cerrar") { dismiss() })
        }
        .alert("¡Gracias por tu apoyo!", isPresented: $showThankYou) {
            Button("¡Genial!") {
                dismiss()
            }
        } message: {
            Text(String(format: NSLocalizedString("support.badgePurchase.available", comment: "Tu badge já está disponível em tu perfil."), badge.name))
        }
    }
    
    private func purchaseBadge() {
        isPurchasing = true
        storeManager.purchaseBadge(badge) { success in
            isPurchasing = false
            if success {
                // ✅ ARREGLADO: Usar authService directamente
                authService.refreshCurrentUser()
                showThankYou = true
            }
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Text(title)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }
}

// MARK: - Store Manager con StoreKit REAL
class StoreManager: NSObject, ObservableObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    @Published var products: [SKProduct] = []
    @Published var isLoading = false
    
    private var productRequest: SKProductsRequest?
    private var purchaseCompletion: ((Bool) -> Void)?
    
    override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    func loadProducts() {
        guard !isLoading else { return }
        
        isLoading = true
        let productIds = Set(Badge.supportBadges.map { $0.productId } + ["com.moments.plus.monthly"])
        productRequest = SKProductsRequest(productIdentifiers: productIds)
        productRequest?.delegate = self
        productRequest?.start()
        
    }
    
    // MARK: - Compra de suscripción REAL
    func purchaseSubscription(completion: @escaping (Bool) -> Void) {
        // Buscar el producto de suscripción
        guard let subscriptionProduct = products.first(where: { $0.productIdentifier == "com.moments.plus.monthly" }) else {
            completion(false)
            return
        }
        
        // Verificar si se pueden hacer compras
        guard SKPaymentQueue.canMakePayments() else {
            completion(false)
            return
        }
        
        
        // Guardar el completion para usarlo cuando termine la compra
        purchaseCompletion = completion
        
        // Crear y agregar el pago a la cola
        let payment = SKPayment(product: subscriptionProduct)
        SKPaymentQueue.default().add(payment)
    }
    
    // MARK: - Compra de badge REAL
    func purchaseBadge(_ badge: Badge, completion: @escaping (Bool) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        // Buscar el producto del badge
        guard let badgeProduct = products.first(where: { $0.productIdentifier == badge.productId }) else {
            completion(false)
            return
        }
        
        // Verificar si se pueden hacer compras
        guard SKPaymentQueue.canMakePayments() else {
            completion(false)
            return
        }
        
        
        // Guardar el completion para usarlo cuando termine la compra
        purchaseCompletion = completion
        
        // Crear y agregar el pago a la cola
        let payment = SKPayment(product: badgeProduct)
        SKPaymentQueue.default().add(payment)
    }
    
    // MARK: - Guardar badge en Firestore (sin cambios)
    private func saveUserBadge(userId: String, badge: UserBadge, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        
        // Primero obtener badges actuales
        db.collection("users").document(userId).getDocument { document, error in
            if let error = error {
                completion(false)
                return
            }
            
            var currentBadges: [UserBadge] = []
            
            if let document = document, document.exists,
               let data = document.data(),
               let badgesData = data["ownedBadges"] as? [[String: Any]] {
                
                let decoder = Firestore.Decoder()
                for badgeDict in badgesData {
                    do {
                        let userBadge = try decoder.decode(UserBadge.self, from: badgeDict)
                        currentBadges.append(userBadge)
                    } catch {
                    }
                }
            }
            
            // Agregar el nuevo badge
            currentBadges.append(badge)
            
            // Encode y guardar
            do {
                let encoder = Firestore.Encoder()
                let badgesData = try currentBadges.map { try encoder.encode($0) }
                
                db.collection("users").document(userId).updateData([
                    "ownedBadges": badgesData,
                    "updatedAt": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        completion(false)
                    } else {
                        completion(true)
                    }
                }
            } catch {
                completion(false)
            }
        }
    }
    
    // MARK: - Guardar suscripción en Firestore
    private func savePlusSubscription(userId: String, completion: @escaping (Bool) -> Void) {
        let subscription = PlusSubscription(
            isActive: true,
            startDate: Date(),
            expiryDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            autoRenew: true,
            plan: "monthly"
        )
        
        let db = Firestore.firestore()
        
        do {
            let encoder = Firestore.Encoder()
            let subscriptionData = try encoder.encode(subscription)
            
            db.collection("users").document(userId).updateData([
                "isPlusSubscriber": true,
                "plusSubscription": subscriptionData,
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(false)
                } else {
                    completion(true)
                }
            }
        } catch {
            completion(false)
        }
    }
    
    // MARK: - SKProductsRequestDelegate
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.products = response.products
            self.isLoading = false
            
            for product in response.products {
            }
            
            if !response.invalidProductIdentifiers.isEmpty {
            }
        }
    }
    
    // MARK: - SKPaymentTransactionObserver
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                handleSuccessfulPurchase(transaction: transaction)
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .restored:
                handleSuccessfulPurchase(transaction: transaction)
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .failed:
                SKPaymentQueue.default().finishTransaction(transaction)
                DispatchQueue.main.async {
                    self.purchaseCompletion?(false)
                    self.purchaseCompletion = nil
                }
                
            case .deferred:
                // No terminar la transacción, esperar
                break
                
            case .purchasing:
                // Transaction is being processed
                break
                
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Manejar compra exitosa
    private func handleSuccessfulPurchase(transaction: SKPaymentTransaction) {
        guard let userId = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.purchaseCompletion?(false)
                self.purchaseCompletion = nil
            }
            return
        }
        
        let productId = transaction.payment.productIdentifier
        
        if productId == "com.moments.plus.monthly" {
            // Es una suscripción
            savePlusSubscription(userId: userId) { [weak self] success in
                DispatchQueue.main.async {
                    self?.purchaseCompletion?(success)
                    self?.purchaseCompletion = nil
                }
            }
        } else {
            // Es un badge
            if let badge = Badge.supportBadges.first(where: { $0.productId == productId }) {
                let userBadge = UserBadge(
                    badgeId: badge.id,
                    name: badge.name,
                    emoji: badge.emoji,
                    colors: badge.colors,
                    price: badge.price
                )
                
                saveUserBadge(userId: userId, badge: userBadge) { [weak self] success in
                    DispatchQueue.main.async {
                        self?.purchaseCompletion?(success)
                        self?.purchaseCompletion = nil
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.purchaseCompletion?(false)
                    self.purchaseCompletion = nil
                }
            }
        }
    }
    
    // MARK: - Restaurar compras
    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}

// MARK: - Extension para precio localizado
extension SKProduct {
    var localizedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price) ?? ""
    }
}

// MARK: - Badge Management View (NUEVA)
struct BadgeManagementView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header con resumen del usuario
                    if let currentUser = authService.currentUser {
                        VStack(spacing: 16) {
                            // Foto grande con decoraciones
                            ZStack {
                                AsyncProfileImageView(userId: currentUser.id)
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                
                                // Anillo Plus
                                if currentUser.isPlusSubscriber {
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 3
                                        )
                                        .frame(width: 108, height: 108)
                                }
                                
                                // Badge principal
                                if let primaryBadge = currentUser.primaryBadge {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: primaryBadge.swiftUIColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 32, height: 32)
                                        
                                        Text(primaryBadge.emoji)
                                            .font(.system(size: 16))
                                    }
                                    .offset(x: 35, y: -35)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                                
                                // Corona Plus
                                if currentUser.isPlusSubscriber {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.8))
                                            .frame(width: 28, height: 28)
                                        
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(Color(hex: "FFD700"))
                                    }
                                    .offset(x: -35, y: -35)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                            }
                            
                            // Info del usuario
                            VStack(spacing: 8) {
                                Text(currentUser.username)
                                    .font(.custom("Poppins-Bold", size: 20))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                HStack(spacing: 8) {
                                    Text("Nivel: \(currentUser.supporterLevel.displayName)")
                                        .font(.custom("Poppins-Medium", size: 14))
                                        .foregroundColor(.gray)
                                    
                                    Text(currentUser.supporterLevel.emoji)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        .padding(.top, 20)
                        
                        // Stats del usuario
                        if currentUser.isPlusSubscriber || currentUser.isSupporter {
                            SupportStatsCard(user: currentUser)
                                .padding(.horizontal, 20)
                        }
                        
                        // Colección de badges
                        BadgeCollectionView(user: currentUser)
                            .padding(.horizontal, 20)
                        
                        // Botón para explorar más badges
                        VStack(spacing: 12) {
                            NavigationLink(destination: SupportMomentsView()) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    
                                    Text(NSLocalizedString("support.badgePurchase.exploreMore", comment: "Explorar más badges"))
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "00A896"))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            if !currentUser.isPlusSubscriber {
                                NavigationLink(destination: SupportMomentsView()) {
                                    HStack {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 16, weight: .bold))
                                        
                                        Text("Obtener Moments Plus")
                                            .font(.custom("Poppins-SemiBold", size: 16))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationTitle("Mis Badges")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }
}
