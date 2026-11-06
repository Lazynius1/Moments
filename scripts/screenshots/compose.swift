// Monta las capturas de tienda: fondo degradado, titular por idioma y la captura con esquinas redondeadas.
// Usa CoreText (fuentes del sistema), así el hindi, japonés, coreano y chino se dibujan bien.
//
// Uso:
//   swift scripts/screenshots/compose.swift <capturas>/<dispositivo> <salida> <iphone|duo|play> [idiomas...]
// Lee headlines.json junto a este script (o el fichero de la variable HEADLINES). Resultado: <salida>/<idioma>/<NN>_<pantalla>.png
import AppKit
import Foundation

struct Layout {
    let canvas: CGSize
    let headlineTop: CGFloat       // margen superior del titular
    let headlineHeight: CGFloat    // alto reservado al titular
    let fontSize: CGFloat
    let shotScale: CGFloat         // escala de la captura respecto al lienzo
    let corner: CGFloat
    let sideMargin: CGFloat
    var cropTop: CGFloat = 0       // píxeles de barra de estado que se recortan de la captura
    var cropBottom: CGFloat = 0    // píxeles de barra de navegación del sistema que se recortan
}

let layouts: [String: Layout] = [
    // iPhone 6,9": 1320 × 2868
    "iphone": Layout(canvas: CGSize(width: 1320, height: 2868), headlineTop: 150, headlineHeight: 400,
                     fontSize: 112, shotScale: 0.86, corner: 100, sideMargin: 90),
    // Google Play, teléfono 9:16: 1080 × 1920 (capturas de Android a 1080 × 2400)
    "play": Layout(canvas: CGSize(width: 1080, height: 1920), headlineTop: 60, headlineHeight: 300,
                   fontSize: 88, shotScale: 0.74, corner: 64, sideMargin: 70, cropTop: 104, cropBottom: 130),
    // iPhone Duo abierto (horizontal): 2853 × 2007
    "duo": Layout(canvas: CGSize(width: 2853, height: 2007), headlineTop: 70, headlineHeight: 310,
                  fontSize: 112, shotScale: 0.76, corner: 56, sideMargin: 200),
]

// Degradado por pantalla (arriba → abajo).
let palettes: [String: (String, String)] = [
    "feed": ("#FF8A3D", "#FF2E7E"),
    "storyViewer": ("#7A3CFF", "#FF3DA5"),
    "hiddenLayers": ("#FFC23D", "#FF5B3D"),
    "chat": ("#9B4DFF", "#4D5BFF"),
    "map": ("#00D4A0", "#0091FF"),
    "privacy": ("#1B1F3B", "#5B2BD6"),
    "appIcons": ("#FF3D6E", "#8A2BFF"),
    "nova": ("#5B3DFF", "#E03DFF"),
]
let order = ["feed", "storyViewer", "hiddenLayers", "chat", "map", "privacy", "appIcons", "nova"]
let fileIndex: [String: String] = [
    "feed": "01", "aiLabel": "02", "storyViewer": "03", "hiddenLayers": "04", "chat": "05",
    "chatInbox": "06", "echo": "07", "map": "08", "privacy": "09", "appIcons": "10", "nova": "11",
]

func color(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

func headlineFont(size: CGFloat, lang: String) -> NSFont {
    let heavy = NSFont.systemFont(ofSize: size, weight: .heavy)
    let base = heavy.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? heavy
    // La fuente del sistema elige sola la tipografía CJK según el idioma del texto; para el chino
    // tradicional y el japonés se fuerza la familia correcta para no mezclar glifos.
    let cjk: [String: String] = ["ja": "Hiragino Sans", "zh-Hant": "PingFang TC", "ko": "Apple SD Gothic Neo"]
    if let family = cjk[lang],
       let font = NSFontManager.shared.font(withFamily: family, traits: .boldFontMask, weight: 9, size: size) {
        return font
    }
    return base
}

func render(shotURL: URL, headline: String, screen: String, lang: String, layout: L, out: URL) throws {
    guard let shot = NSImage(contentsOf: shotURL),
          let shotRep = shot.representations.first else { throw NSError(domain: "compose", code: 1) }
    let shotPixels = CGSize(width: CGFloat(shotRep.pixelsWide),
                            height: CGFloat(shotRep.pixelsHigh) - layout.cropTop - layout.cropBottom)
    // Parte visible de la captura en las coordenadas de NSImage (origen abajo): sin barras del sistema.
    let pointsPerPixel = shot.size.height / CGFloat(shotRep.pixelsHigh)
    let sourceRect = NSRect(x: 0, y: layout.cropBottom * pointsPerPixel, width: shot.size.width,
                            height: shot.size.height - (layout.cropTop + layout.cropBottom) * pointsPerPixel)
    let canvas = layout.canvas
    // Lienzo sRGB sin canal alfa (App Store rechaza PNG con alfa)
    let cg = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                       bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Fondo
    let (top, bottom) = palettes[screen] ?? ("#7B5BFF", "#C04BFF")
    NSGradient(starting: color(top), ending: color(bottom))!.draw(in: NSRect(origin: .zero, size: canvas), angle: -90)

    // Titular (coordenadas de AppKit: origen abajo a la izquierda)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineHeightMultiple = 1.02
    var fontSize = layout.fontSize
    let textWidth = canvas.width - layout.sideMargin * 2
    var attributed: NSAttributedString
    var bounds: NSRect
    var lineHeight: CGFloat = 0
    repeat {
        let font = headlineFont(size: fontSize, lang: lang)
        lineHeight = NSLayoutManager().defaultLineHeight(for: font) * paragraph.lineHeightMultiple
        attributed = NSAttributedString(string: headline, attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        bounds = attributed.boundingRect(with: NSSize(width: textWidth, height: 10_000),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
        fontSize -= 4
    } while (bounds.height > layout.headlineHeight || bounds.height > lineHeight * 2.5) && fontSize > 40  // máximo 2 líneas
    let textY = canvas.height - layout.headlineTop - layout.headlineHeight / 2 - bounds.height / 2
    attributed.draw(with: NSRect(x: layout.sideMargin, y: textY, width: textWidth, height: bounds.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])

    // Captura
    let shotWidth = canvas.width * layout.shotScale
    let shotHeight = shotWidth * shotPixels.height / shotPixels.width
    let shotTop = layout.headlineTop + layout.headlineHeight + 40
    let shotRect = NSRect(x: (canvas.width - shotWidth) / 2, y: canvas.height - shotTop - shotHeight,
                          width: shotWidth, height: shotHeight)
    let clip = NSBezierPath(roundedRect: shotRect, xRadius: layout.corner, yRadius: layout.corner)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.set()
    NSColor.white.setFill()
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    shot.draw(in: shotRect, from: sourceRect, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    try NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!.write(to: out)
}
typealias L = Layout

let args = CommandLine.arguments
guard args.count >= 4, let layout = layouts[args[3]] else {
    print("Uso: swift compose.swift <capturas>/<dispositivo> <salida> <iphone|duo|play> [idiomas...]")
    exit(1)
}
let source = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let headlines = try JSONSerialization.jsonObject(
    with: Data(contentsOf: ProcessInfo.processInfo.environment["HEADLINES"].map { URL(fileURLWithPath: $0) }
        ?? scriptDir.appendingPathComponent("headlines.json"))) as! [String: Any]
let langs = args.count > 4 ? Array(args[4...])
    : (try FileManager.default.contentsOfDirectory(atPath: source.path)).filter { !$0.hasPrefix(".") }.sorted()

for lang in langs {
    guard let copy = headlines[lang] as? [String: String] else { print("sin titulares: \(lang)"); continue }
    let dir = output.appendingPathComponent(lang)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (position, screen) in order.enumerated() {
        let shotURL = source.appendingPathComponent(lang).appendingPathComponent("\(fileIndex[screen]!)_\(screen).png")
        guard FileManager.default.fileExists(atPath: shotURL.path) else { print("falta \(shotURL.path)"); continue }
        let out = dir.appendingPathComponent(String(format: "%02d_%@.png", position + 1, screen))
        try render(shotURL: shotURL, headline: copy[screen] ?? "", screen: screen, lang: lang, layout: layout, out: out)
    }
    print("✓ \(lang)")
}
