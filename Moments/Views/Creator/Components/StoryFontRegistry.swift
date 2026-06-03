import UIKit
import CoreText

enum StoryFontRegistry {
    private static var didRegister = false
    private static var postScriptByFile: [String: String] = [:]

    static let bundledFiles: [String] = [
        "BebasNeue-Regular",
        "Lora-Regular",
        "Anton-Regular",
        "Pacifico-Regular",
        "VarelaRound-Regular",
        "BarlowCondensed-Bold",
        "PlayfairDisplay-Bold",
        "IBMPlexSerif-Regular",
        "PoiretOne-Regular",
        "Caveat-Bold",
        "Bangers-Regular",
        "DancingScript-Bold",
        "CormorantGaramond-Italic"
    ]

    static func registerFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        for name in bundledFiles {
            guard let url = fontURL(fileName: name) else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if let dataProvider = CGDataProvider(url: url as CFURL),
               let cgFont = CGFont(dataProvider),
               let psName = cgFont.postScriptName as String? {
                postScriptByFile[name] = psName
            }
        }
    }

    static func uiFont(fileName: String, size: CGFloat) -> UIFont? {
        registerFontsIfNeeded()
        if let psName = postScriptByFile[fileName] ?? resolvedPostScript(fileName: fileName),
           let font = UIFont(name: psName, size: size) {
            return font
        }
        return nil
    }

    private static func resolvedPostScript(fileName: String) -> String? {
        guard let url = fontURL(fileName: fileName),
              let dataProvider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(dataProvider) else { return nil }
        return cgFont.postScriptName as String?
    }

    private static func fontURL(fileName: String) -> URL? {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "ttf", subdirectory: "Resources/Fonts") {
            return url
        }
        return Bundle.main.url(forResource: fileName, withExtension: "ttf")
    }
}
