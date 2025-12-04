// MARK: - iOS Types Stubs for Android-only compilation
// These stubs allow Swift code that references iOS types to compile
// Skip will transpile these to appropriate Android types

import Foundation
import SwiftUI

// MARK: - UIKit Stubs
// UIApplication available outside #if SKIP for AppDelegate compatibility
public typealias UIApplication = Any

// Android-only compilation - all stubs are always available
// Android doesn't use UIKit - these are stubs for compilation
public typealias UIView = Any
public typealias UIImage = Any
public typealias UIColor = Color
public typealias UIFont = Font
public typealias UIViewController = Any
public typealias UIButton = Any
public typealias UILabel = Any
public typealias UIImageView = Any
public typealias UIWindowScene = Any
public typealias UIGraphicsImageRenderer = Any
public typealias AVPlayerViewController = Any
public typealias UIStackView = Any

public class UIActivityViewController: NSObject {
    public init(activityItems: [Any], applicationActivities: [Any]?) {
        super.init()
    }
    public var popoverPresentationController: UIPopoverPresentationController? { return nil }
}

public class UIPopoverPresentationController: NSObject {
    public var sourceView: Any? = nil
    public var sourceRect: CGRect = .zero
}

// MARK: - SwiftUI Representable Stubs for Android
public protocol UIViewRepresentable: View {
    associatedtype UIViewType
    func makeUIView(context: Context) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: Context)
}

public protocol UIViewControllerRepresentable: View {
    associatedtype UIViewControllerType
    func makeUIViewController(context: Context) -> UIViewControllerType
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)
}

public struct Context {
    // Placeholder context for Representable protocols
}

// MARK: - UIApplication LaunchOptionsKey Stub
public struct UIApplicationLaunchOptionsKey: Hashable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public typealias NSLayoutConstraint = Any

// MARK: - CoreGraphics Stubs
public struct CGSize {
    public var width: CGFloat
    public var height: CGFloat
    
    public static let zero = CGSize(width: 0, height: 0)
    
    public init(width: CGFloat = 0, height: CGFloat = 0) {
        self.width = width
        self.height = height
    }
}

public struct CGPoint {
    public var x: CGFloat
    public var y: CGFloat
    
    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

// MARK: - CGRect Stub (struct instead of typealias for extension support)
public struct CGRect {
    public var origin: CGPoint
    public var size: CGSize
    
    public var width: CGFloat {
        // Placeholder - will be handled natively on Android
        return 375.0
    }
    
    public var height: CGFloat {
        // Placeholder - will be handled natively on Android
        return 812.0
    }
    
    public init(origin: CGPoint = CGPoint(x: 0, y: 0), size: CGSize = CGSize()) {
        self.origin = origin
        self.size = size
    }
    
    public init(width: CGFloat, height: CGFloat) {
        self.origin = CGPoint(x: 0, y: 0)
        self.size = CGSize()
        // Note: width and height stored separately for Android compatibility
    }
    
    public static let zero = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0))
}

// Stub classes
public class NSObject {
    public init() {}
}

public class NSCoder {
    public init() {}
}

// MARK: - UIDevice Stub (always available for Android-only compilation)
public class UIDevice {
    public static let current = UIDevice()
    
    public var identifierForVendor: UUID? {
        // Android: Use Settings.Secure.ANDROID_ID or similar
        // Skip will transpile this appropriately
        return UUID()
    }
    
    public var model: String {
        // Android: Use Build.MODEL or similar
        return "Android Device"
    }
    
    public var systemVersion: String {
        // Android: Use Build.VERSION.RELEASE or similar
        return "Unknown"
    }
    
    private init() {}
}

// MARK: - Bundle Stub
public class Bundle {
    public static let main = Bundle()
    
    public var infoDictionary: [String: Any]? {
        // Android: Use AndroidManifest.xml or BuildConfig
        // Skip will transpile this appropriately
        return ["CFBundleShortVersionString": "1.0.0"]
    }
    
    public var bundleURL: URL {
        // Android: Return a placeholder URL
        // Skip will transpile this appropriately
        return URL(fileURLWithPath: "/")
    }
    
    public func object(forInfoDictionaryKey key: String) -> Any? {
        return infoDictionary?[key]
    }
    
    public init?(path: String) {
        // Android: Bundle initialization will be handled natively
        // Return nil for placeholder
    }
    
    private init() {}
}

// MARK: - UserDefaults Stub
public class UserDefaults {
    public static let standard = UserDefaults()
    
    private var storage: [String: Any] = [:]
    
    public func string(forKey key: String) -> String? {
        return storage[key] as? String
    }
    
    public func double(forKey key: String) -> Double {
        return (storage[key] as? Double) ?? 0.0
    }
    
    public func set(_ value: Any?, forKey key: String) {
        if let value = value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }
    
    public func object(forKey key: String) -> Any? {
        return storage[key]
    }
    
    private init() {}
}

// MARK: - UIApplicationDelegate Stub (available outside #if SKIP for Skip compilation)
// Android: UIApplicationDelegate is just AnyObject for compatibility
public protocol UIApplicationDelegate: AnyObject {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]?) -> Bool
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error)
}

// MARK: - CoreLocation Stubs (available outside #if SKIP for Skip compilation)
public struct CLLocationCoordinate2D: Equatable {
    public var latitude: Double
    public var longitude: Double
    
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - MapKit Stubs
public struct MKCoordinateRegion {
    public var center: CLLocationCoordinate2D
    public var span: MKCoordinateSpan
    
    public init(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        self.center = center
        self.span = span
    }
}

public struct MKCoordinateSpan {
    public var latitudeDelta: Double
    public var longitudeDelta: Double
    
    public init(latitudeDelta: Double, longitudeDelta: Double) {
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

public class CLLocationManager {
    public var delegate: CLLocationManagerDelegate? = nil
    public var desiredAccuracy: Double = 0.0
    
    public init() {}
    
    public func requestWhenInUseAuthorization() {}
    public func requestAlwaysAuthorization() {}
    public func startUpdatingLocation() {}
    public func stopUpdatingLocation() {}
    public func requestLocation() {}
    
    public var authorizationStatus: CLAuthorizationStatus {
        return .notDetermined
    }
}

public protocol CLLocationManagerDelegate: AnyObject {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
}

public class CLLocation {
    public var coordinate: CLLocationCoordinate2D
    public var altitude: Double
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double
    public var timestamp: Date
    
    public init(coordinate: CLLocationCoordinate2D, altitude: Double = 0, horizontalAccuracy: Double = 0, verticalAccuracy: Double = 0, timestamp: Date = Date()) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
    }
}

public let kCLLocationAccuracyThreeKilometers: Double = 3000.0
public let kCLLocationAccuracyBest: Double = 0.0
public let kCLLocationAccuracyNearestTenMeters: Double = 10.0

public enum CLAuthorizationStatus: Int32 {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorizedAlways = 3
    case authorizedWhenInUse = 4
}

public class CLGeocoder {
    public func reverseGeocodeLocation(_ location: CLLocation, completionHandler: @escaping ([CLPlacemark]?, Error?) -> Void) {
        // Android: Geocoding will be handled natively
        completionHandler(nil, nil)
    }
    
    public init() {}
}

public class CLPlacemark {
    public var name: String? { return nil }
    public var locality: String? { return nil }
    public var administrativeArea: String? { return nil }
    public var country: String? { return nil }
    public var postalCode: String? { return nil }
    public var subThoroughfare: String? { return nil }
    public var thoroughfare: String? { return nil }
}

// MARK: - UserNotifications Stubs
public class UNUserNotificationCenter {
    public static func current() -> UNUserNotificationCenter {
        return UNUserNotificationCenter()
    }
    
    public var delegate: UNUserNotificationCenterDelegate?
    
    public func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping (Bool, Error?) -> Void) {
        // Android: Notification authorization will be handled natively
        completionHandler(false, nil)
    }
    
    private init() {}
}

public struct UNAuthorizationOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 2)
}

public protocol UNUserNotificationCenterDelegate: AnyObject {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)
}

public struct UNNotification {
    public let request: UNNotificationRequest
    public init(request: UNNotificationRequest) {
        self.request = request
    }
}

public struct UNNotificationRequest {
    public let content: UNNotificationContent
    public init(content: UNNotificationContent) {
        self.content = content
    }
}

public struct UNNotificationContent {
    public var userInfo: [AnyHashable: Any] = [:]
}

public struct UNNotificationPresentationOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 2)
}

public struct UNNotificationResponse {
    public let notification: UNNotification
    public init(notification: UNNotification) {
        self.notification = notification
    }
}

// MARK: - Firebase DocumentID Stub
// Property wrapper that mimics @DocumentID behavior
@propertyWrapper
public struct DocumentID {
    public var wrappedValue: String?
    
    public init(wrappedValue: String? = nil) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: - UIPasteboard Stub
public class UIPasteboard {
    public static let general = UIPasteboard()
    
    public var string: String? {
        get { return nil }
        set { /* Android: Clipboard will be handled natively */ }
    }
    
    private init() {}
}

// MARK: - UIScreen Stub
public class UIScreen {
    public static let main = UIScreen()
    
    public var bounds: CGRect {
        // Android: Screen bounds will be handled natively
        return CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize()) // Placeholder
    }
    
    private init() {}
}

// CGRect extension removed - properties are now part of the struct definition

// MARK: - UIImpactFeedbackGenerator Stub
public class UIImpactFeedbackGenerator {
    public enum Style {
        case light
        case medium
        case heavy
    }
    
    // Alias for compatibility
    public typealias FeedbackStyle = Style
    
    public init(style: Style) {
        // Android: Haptic feedback will be handled natively
    }
    
    public func impactOccurred() {
        // Android: Haptic feedback will be handled natively
    }
}

// MARK: - UIRectCorner Stub
public struct UIRectCorner: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    public static let topLeft = UIRectCorner(rawValue: 1 << 0)
    public static let topRight = UIRectCorner(rawValue: 1 << 1)
    public static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    public static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    public static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

// MARK: - PencilKit Stubs for Android
public class PKCanvasView: NSObject {
    public var backgroundColor: UIColor? = nil
    public var isOpaque: Bool = false
    public var drawingPolicy: Any = 0
    public var tool: Any? = nil
    
    public override init() {
        super.init()
    }
    
    public func becomeFirstResponder() -> Bool { return false }
    public func addObserver(_ observer: Any) {}
    public func setVisible(_ visible: Bool, forFirstResponder responder: Any) {}
}

public class PKToolPicker: NSObject {
    public override init() {
        super.init()
    }
    
    public func setVisible(_ visible: Bool, forFirstResponder responder: Any) {}
    public func addObserver(_ observer: Any) {}
}

public class PKInkingTool {
    public enum InkType {
        case pen
        case marker
        case pencil
    }
    
    public init(_ type: InkType, color: UIColor, width: CGFloat) {}
}

// MARK: - PhotosUI Stubs
public class PHPickerViewController: NSObject {
    public var delegate: Any? = nil
    
    public init(configuration: PHPickerConfiguration) {
        super.init()
    }
}

public class PHPickerConfiguration: NSObject {
    public var filter: PHPickerFilter = .any(of: [])
    public var selectionLimit: Int = 1
    public var preferredAssetRepresentationMode: PHPickerConfiguration.AssetRepresentationMode = .current
    
    public enum AssetRepresentationMode {
        case current
        case compatible
    }
}

public enum PHPickerFilter {
    case any(of: [PHPickerFilter])
    case images
    case videos
    case livePhotos
}

public protocol PHPickerViewControllerDelegate: AnyObject {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult])
}

public class PHPickerResult: NSObject {
    public let itemProvider: NSItemProvider
    
    public init(itemProvider: NSItemProvider) {
        self.itemProvider = itemProvider
        super.init()
    }
}

public class NSItemProvider: NSObject {
    public func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        return false
    }
    
    public func loadObject(ofClass: AnyClass, completionHandler: @escaping (Any?, Error?) -> Void) {}
    public func loadDataRepresentation(forTypeIdentifier: String, completionHandler: @escaping (Data?, Error?) -> Void) {}
}

// MARK: - UIImagePickerController Stubs
public class UIImagePickerController: NSObject {
    public enum SourceType {
        case photoLibrary
        case camera
        case savedPhotosAlbum
    }
    
    public var sourceType: SourceType = .photoLibrary
    public var mediaTypes: [String] = []
    public var delegate: Any? = nil
    public var videoQuality: Any = 0
    public var videoMaximumDuration: TimeInterval = 60
    
    public override init() {
        super.init()
    }
}

public protocol UIImagePickerControllerDelegate: AnyObject {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any])
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController)
}

public protocol UINavigationControllerDelegate: AnyObject {}

public extension UIImagePickerController {
    enum InfoKey {
        case originalImage
        case mediaURL
    }
    
    enum CameraDevice {
        case rear
        case front
    }
}

// MARK: - UTType Stubs
public struct UTType {
    public static let image = UTType()
    public static let movie = UTType()
    
    public var identifier: String {
        return "public.image"
    }
}

// Helper colors for compatibility
public extension Color {
    static var systemBackground: Color { Color.white }
    static var systemGray6: Color { Color.gray.opacity(0.1) }
    static var secondarySystemBackground: Color { Color.gray.opacity(0.05) }
}
