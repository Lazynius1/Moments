// Dibuja los textos y tarjetas del vídeo de previsualización como secuencias PNG (886 × 1920, 30 fps).
// Uso: swift scripts/preview/overlays.swift <spec.json> <salida>
//
// spec.json: { "logo": "<png>", "items": [ { "name", "kind": "pill" | "card" | "logo", "text",
//   "frames", "typeFrames", "y" (0-1, centro del texto), "colors": ["#hex", "#hex"] } ] }
// - pill: texto escrito letra a letra sobre una píldora de color, fondo transparente (va encima del vídeo);
//   `delayFrames` retrasa el inicio de la escritura.
// - card: degradado a pantalla completa con el texto escrito letra a letra.
// - logo: degradado con el logotipo que aparece con un fundido.
import AppKit
import Foundation

let size = CGSize(width: 886, height: 1920)

struct Item: Decodable {
    let name: String
    let kind: String
    let text: String?
    let frames: Int
    let typeFrames: Int?
    let y: Double?
    let colors: [String]?
    let fontSize: Double?
    let delayFrames: Int?
}

struct Spec: Decodable {
    let logo: String?
    let items: [Item]
}

func color(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

func roundedFont(_ size: CGFloat) -> NSFont {
    let heavy = NSFont.systemFont(ofSize: size, weight: .heavy)
    return heavy.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? heavy
}

func attributed(_ text: String, size: CGFloat) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1.0
    return NSAttributedString(string: text, attributes: [
        .font: roundedFont(size), .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
    ])
}

/// Texto visible en el fotograma: letra a letra (grafemas, así los emoji salen enteros).
func typed(_ text: String, frame: Int, typeFrames: Int) -> String {
    let characters = Array(text)
    guard typeFrames > 0 else { return text }
    let count = min(characters.count, Int((Double(frame + 1) / Double(typeFrames)) * Double(characters.count)))
    return String(characters.prefix(max(count, 0)))
}

func gradient(_ colors: [String]) -> NSGradient {
    NSGradient(starting: color(colors.first ?? "#7A3CFF"), ending: color(colors.last ?? "#FF3DA5"))!
}

func render(_ draw: () -> Void) -> Data {
    let cg = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
}

let maxWidth = size.width - 120

func drawCentered(_ text: NSAttributedString, centerY: CGFloat) -> NSRect {
    let bounds = text.boundingRect(with: NSSize(width: maxWidth, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let rect = NSRect(x: (size.width - maxWidth) / 2, y: centerY - bounds.height / 2, width: maxWidth, height: bounds.height)
    text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    return NSRect(x: (size.width - bounds.width) / 2, y: rect.minY, width: bounds.width, height: bounds.height)
}

let args = CommandLine.arguments
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let output = URL(fileURLWithPath: args[2])
let logo = spec.logo.flatMap { NSImage(contentsOfFile: $0) }

for item in spec.items {
    let dir = output.appendingPathComponent(item.name)
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let text = item.text ?? ""
    let typeFrames = item.typeFrames ?? 18
    let delay = item.delayFrames ?? 0   // fotogramas sin texto antes de empezar a escribir
    // Coordenadas de AppKit: origen abajo; `y` del spec se mide desde arriba.
    let centerY = size.height * (1 - CGFloat(item.y ?? 0.5))

    for frame in 0..<item.frames {
        let data = render {
            switch item.kind {
            case "card":
                gradient(item.colors ?? []).draw(in: NSRect(origin: .zero, size: size), angle: -90)
                let shown = typed(text, frame: frame, typeFrames: typeFrames)
                _ = drawCentered(attributed(shown.isEmpty ? " " : shown, size: CGFloat(item.fontSize ?? 104)), centerY: centerY)
            case "logo":
                gradient(item.colors ?? []).draw(in: NSRect(origin: .zero, size: size), angle: -90)
                if let logo {
                    let alpha = min(1, Double(frame) / 12)
                    let scale = 0.92 + 0.08 * alpha
                    let width = 640 * scale
                    let height = width * logo.size.height / logo.size.width
                    logo.draw(in: NSRect(x: (size.width - width) / 2, y: centerY - height / 2, width: width, height: height),
                              from: .zero, operation: .sourceOver, fraction: alpha)
                }
            default: // pill
                guard frame >= delay else { return }
                let shown = typed(text, frame: frame - delay, typeFrames: typeFrames)
                guard !shown.isEmpty else { return }
                let string = attributed(shown, size: CGFloat(item.fontSize ?? 64))
                let bounds = string.boundingRect(with: NSSize(width: maxWidth - 60, height: 2000),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading])
                let pill = NSRect(x: (size.width - bounds.width) / 2 - 34, y: centerY - bounds.height / 2 - 22,
                                  width: bounds.width + 68, height: bounds.height + 44)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
                shadow.shadowBlurRadius = 24
                shadow.shadowOffset = NSSize(width: 0, height: -6)
                shadow.set()
                let path = NSBezierPath(roundedRect: pill, xRadius: 36, yRadius: 36)
                path.addClip()
                gradient(item.colors ?? []).draw(in: pill, angle: 0)
                NSGraphicsContext.restoreGraphicsState()
                string.draw(with: NSRect(x: pill.minX + 34, y: pill.minY + 22, width: bounds.width, height: bounds.height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
        try data.write(to: dir.appendingPathComponent(String(format: "%04d.png", frame)))
    }
    print("✓ \(item.name) (\(item.frames) fotogramas)")
}
