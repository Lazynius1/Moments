// MARK: - AdMob Types for Skip (Android)
// These types allow Swift code to compile while Skip transpiles to Android AdMob SDK

import Foundation
import SwiftUI

// MARK: - Native Ad Model
public class NativeAd {
    public var headline: String?
    public var body: String?
    public var advertiser: String?
    public var callToAction: String?
    public var icon: NativeAdImage?
    public var image: NativeAdImage?
    public var mediaContent: MediaContent
    public var starRating: NSNumber?
    public var price: String?
    public var store: String?
    
    public init() {
        self.mediaContent = MediaContent()
    }
}

public class NativeAdImage {
    public var imageURL: URL?
    
    public init() {}
}

public class MediaContent {
    public var hasVideoContent: Bool = false
    public var videoController: VideoController
    
    public init() {
        self.videoController = VideoController()
    }
}

public class VideoController {
    public var delegate: VideoControllerDelegate?
    public var isMuted: Bool = false
    
    public init() {}
}

public protocol VideoControllerDelegate: AnyObject {
    func videoControllerDidPlayVideo(_ videoController: VideoController)
    func videoControllerDidPauseVideo(_ videoController: VideoController)
    func videoControllerDidEndVideoPlayback(_ videoController: VideoController)
    func videoControllerDidMuteVideo(_ videoController: VideoController)
    func videoControllerDidUnmuteVideo(_ videoController: VideoController)
}

// MARK: - Ad Loader
public class AdLoader: NSObject {
    private let adUnitID: String
    private let adTypes: [AdType]
    
    public weak var delegate: AdLoaderDelegate?
    
    public init(adUnitID: String, rootViewController: Any?, adTypes: [AdType], options: [Any]) {
        self.adUnitID = adUnitID
        self.adTypes = adTypes
        super.init()
    }
    
    public func load(_ request: AdRequest) {
        // Skip transpiles this to Android AdMob SDK
        // AdLoader -> com.google.android.gms.ads.AdLoader
        // NativeAd -> com.google.android.gms.ads.nativead.NativeAd
        // Skip will bridge the delegate pattern to Android callbacks
        
        // Actual loading happens when Skip transpiles to Kotlin
        // The Android SDK will be used natively:
        // val adLoader = AdLoader.Builder(context, adUnitID)
        //     .forNativeAd { nativeAd -> 
        //         delegate?.adLoader(this, didReceive: nativeAd)
        //     }
        //     .build()
        // adLoader.loadAd(AdRequest.Builder().build())
        
        // For compilation, we simulate async behavior
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Skip replaces this with actual Android AdMob SDK call
        }
    }
}

public enum AdType {
    case native
}

public protocol AdLoaderDelegate: AnyObject {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error)
}

public protocol NativeAdLoaderDelegate: AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd)
}

// MARK: - Ad Request
public class AdRequest {
    public init() {}
}

// MARK: - Ad Options
public class NativeAdMediaAdLoaderOptions {
    public var mediaAspectRatio: MediaAspectRatio = .any
    
    public init() {}
}

public enum MediaAspectRatio {
    case any
    case landscape
    case portrait
    case square
}

// MARK: - Native Ad View (Android - Skip transpiles these)
public class NativeAdView {
    public var nativeAd: NativeAd?
    public var headlineView: Any?
    public var bodyView: Any?
    public var callToActionView: Any?
    public var iconView: Any?
    public var imageView: Any?
    public var mediaView: MediaView?
    public var advertiserView: Any?
    public var adChoicesView: AdChoicesView?
    public var starRatingView: Any?
    public var priceView: Any?
    public var storeView: Any?
    
    public func addSubview(_ view: Any) {
        // Skip will transpile this to Android view hierarchy
    }
    
    public init() {}
}

public class MediaView {
    public var mediaContent: MediaContent?
    public var contentMode: ContentMode = .fit
    public var backgroundColor: Color?
    
    public init() {}
}

public class AdChoicesView {
    public init() {}
}

public enum ContentMode {
    case fit
    case fill
    case scaleAspectFit
    case scaleAspectFill
}

// MARK: - UIView Stubs for Android
// Note: UIView, UILabel, UIButton are already defined in IOSTypesStubs.swift
