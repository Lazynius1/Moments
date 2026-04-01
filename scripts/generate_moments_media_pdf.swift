import Foundation
import AppKit
import CoreGraphics

struct Palette {
    static let bg = NSColor(calibratedRed: 0.972, green: 0.957, blue: 0.937, alpha: 1.0)
    static let panel = NSColor.white
    static let ink = NSColor(calibratedRed: 0.067, green: 0.071, blue: 0.094, alpha: 1.0)
    static let muted = NSColor(calibratedRed: 0.400, green: 0.412, blue: 0.471, alpha: 1.0)
    static let line = NSColor(calibratedRed: 0.862, green: 0.851, blue: 0.820, alpha: 1.0)
    static let blue = NSColor(calibratedRed: 0.255, green: 0.345, blue: 0.816, alpha: 1.0)
    static let pink = NSColor(calibratedRed: 0.784, green: 0.314, blue: 0.753, alpha: 1.0)
    static let gold = NSColor(calibratedRed: 1.0, green: 0.800, blue: 0.439, alpha: 1.0)
    static let dark = NSColor(calibratedRed: 0.043, green: 0.071, blue: 0.082, alpha: 1.0)
    static let soft = NSColor(calibratedRed: 0.941, green: 0.925, blue: 0.898, alpha: 1.0)
}

enum Font {
    static func heavy(_ size: CGFloat) -> NSFont { NSFont.systemFont(ofSize: size, weight: .heavy) }
    static func bold(_ size: CGFloat) -> NSFont { NSFont.systemFont(ofSize: size, weight: .bold) }
    static func semibold(_ size: CGFloat) -> NSFont { NSFont.systemFont(ofSize: size, weight: .semibold) }
    static func medium(_ size: CGFloat) -> NSFont { NSFont.systemFont(ofSize: size, weight: .medium) }
    static func regular(_ size: CGFloat) -> NSFont { NSFont.systemFont(ofSize: size, weight: .regular) }
}

struct Assets {
    let logo = "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/Glowsy/Resources/Assets.xcassets/LoginLogo.imageset/logotipo blanco con degradado.png"
    let feed = "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/docs/marketing/screenshots/1 feed.PNG"
    let creator = "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/docs/marketing/screenshots/2 creator .PNG"
    let audience = "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/docs/marketing/screenshots/3 audience.PNG"
    let echoes = "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/docs/marketing/screenshots/4 echoes.PNG"
    let maps = "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/docs/marketing/screenshots/5 maps.PNG"
    let privacy = "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/docs/marketing/screenshots/6 privacy.PNG"
}

final class PDFRenderer {
    let width: CGFloat = 595
    let height: CGFloat = 842
    let margin: CGFloat = 42
    let outputURL: URL
    let assets = Assets()

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func render() throws {
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "PDFRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create PDF context"])
        }

        page(in: context, drawCover)
        page(in: context, drawProductPages)
        page(in: context, drawPrivacyPage)
        page(in: context, drawEchoPage)
        page(in: context, drawComparisonPage)

        context.closePDF()
    }

    private func page(in context: CGContext, _ draw: () -> Void) {
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw()
        NSGraphicsContext.current = nil
        context.restoreGState()
        context.endPDFPage()
    }

    private func fill(_ rect: CGRect, color: NSColor, radius: CGFloat = 0) {
        color.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.fill()
    }

    private func stroke(_ rect: CGRect, color: NSColor, lineWidth: CGFloat = 1, radius: CGFloat = 0) {
        color.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.lineWidth = lineWidth
        path.stroke()
    }

    @discardableResult
    private func text(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat, font: NSFont, color: NSColor = Palette.ink, lineHeight: CGFloat? = nil) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        if let lineHeight {
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        }
        let attr = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ])
        let rect = CGRect(x: x, y: y, width: width, height: .greatestFiniteMagnitude)
        let size = attr.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        attr.draw(in: CGRect(x: x, y: y, width: width, height: ceil(size.height) + 2))
        return ceil(size.height)
    }

    private func centeredText(_ string: String, rect: CGRect, font: NSFont, color: NSColor = Palette.ink) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ])
        attr.draw(in: rect)
    }

    private func chip(_ title: String, x: CGFloat, y: CGFloat) -> CGFloat {
        let paddingX: CGFloat = 12
        let width = ceil((title as NSString).size(withAttributes: [.font: Font.medium(11)]).width) + paddingX * 2
        fill(CGRect(x: x, y: y, width: width, height: 26), color: NSColor.white.withAlphaComponent(0.88), radius: 13)
        stroke(CGRect(x: x, y: y, width: width, height: 26), color: Palette.ink.withAlphaComponent(0.08), radius: 13)
        centeredText(title, rect: CGRect(x: x + 4, y: y + 6, width: width - 8, height: 14), font: Font.medium(11), color: Palette.dark)
        return width
    }

    private func placeImage(path: String, in rect: CGRect, radius: CGFloat = 22, background: NSColor = Palette.panel) {
        fill(rect, color: background, radius: radius)
        stroke(rect, color: Palette.line, lineWidth: 1, radius: radius)
        guard let image = NSImage(contentsOfFile: path) else { return }

        let insetRect = rect.insetBy(dx: 10, dy: 10)
        let imageSize = image.size
        let scale = min(insetRect.width / imageSize.width, insetRect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: insetRect.midX - drawSize.width / 2,
            y: insetRect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }

    private func titleBlock(eyebrow: String, title: String, body: String, top: CGFloat) {
        _ = text(eyebrow.uppercased(), x: margin, y: top, width: width - margin * 2, font: Font.semibold(10), color: Palette.muted)
        _ = text(title, x: margin, y: top + 18, width: width - margin * 2, font: Font.heavy(28), color: Palette.dark, lineHeight: 30)
        _ = text(body, x: margin, y: top + 82, width: width - margin * 2 - 40, font: Font.regular(14), color: Palette.ink, lineHeight: 21)
    }

    private func drawCover() {
        let pageRect = CGRect(x: 18, y: 18, width: width - 36, height: height - 36)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.984, green: 0.980, blue: 0.965, alpha: 1),
            NSColor(calibratedRed: 0.949, green: 0.933, blue: 0.906, alpha: 1)
        ])!
        let path = NSBezierPath(roundedRect: pageRect, xRadius: 28, yRadius: 28)
        gradient.draw(in: path, angle: 135)
        stroke(pageRect, color: Palette.ink.withAlphaComponent(0.06), radius: 28)

        let orb1 = NSBezierPath(ovalIn: CGRect(x: 30, y: 18, width: 200, height: 200))
        NSColor(calibratedRed: 0.255, green: 0.345, blue: 0.816, alpha: 0.12).setFill()
        orb1.fill()
        let orb2 = NSBezierPath(ovalIn: CGRect(x: 360, y: 20, width: 170, height: 170))
        NSColor(calibratedRed: 0.784, green: 0.314, blue: 0.753, alpha: 0.12).setFill()
        orb2.fill()
        let orb3 = NSBezierPath(ovalIn: CGRect(x: 310, y: 560, width: 210, height: 210))
        NSColor(calibratedRed: 1, green: 0.8, blue: 0.439, alpha: 0.12).setFill()
        orb3.fill()

        _ = text("DOSSIER BREVE PARA MEDIOS Y TELEVISIÓN", x: 54, y: 64, width: 280, font: Font.semibold(11), color: Palette.muted)

        if let logo = NSImage(contentsOfFile: assets.logo) {
            logo.draw(in: CGRect(x: 54, y: 112, width: 140, height: 60))
        } else {
            _ = text("Moments", x: 54, y: 114, width: 200, font: Font.heavy(42), color: Palette.dark)
        }

        _ = text("Una red social móvil pensada para compartir mejor, no para compartir más.", x: 54, y: 200, width: 430, font: Font.heavy(32), color: Palette.dark, lineHeight: 36)
        _ = text("Moments combina momentos, historias, audiencias modulares, archivo y una capa colaborativa propia llamada Echo. La propuesta no es copiar a otra red social: es reorganizar cómo, con quién y para cuánto tiempo compartimos.", x: 54, y: 330, width: 420, font: Font.regular(17), color: Palette.ink, lineHeight: 27)

        var chipX: CGFloat = 54
        let chipY: CGFloat = 458
        for title in ["Privacidad modular", "Momentos e historias", "Echo colaborativo", "Archivo y memoria"] {
            let w = chip(title, x: chipX, y: chipY)
            chipX += w + 8
        }

        fill(CGRect(x: 54, y: 516, width: 430, height: 108), color: Palette.dark.withAlphaComponent(0.04), radius: 22)
        stroke(CGRect(x: 54, y: 516, width: 430, height: 108), color: Palette.dark.withAlphaComponent(0.06), radius: 22)
        _ = text("“Las redes sociales no tienen por qué ser todo o nada. También pueden ser modulares, más contextuales y más humanas.”", x: 74, y: 544, width: 390, font: Font.medium(22), color: Palette.dark, lineHeight: 30)

        _ = text("Documento de posicionamiento editorial · Moments · marzo 2026", x: 54, y: 760, width: 400, font: Font.regular(11), color: Palette.muted)
    }

    private func drawProductPages() {
        fill(CGRect(x: 0, y: 0, width: width, height: height), color: Palette.bg)
        titleBlock(
            eyebrow: "01 · Qué es Moments",
            title: "Una red social construida alrededor del contexto",
            body: "Moments parte de una idea simple: no todo lo que compartimos tiene que ir a la misma audiencia ni vivir con la misma lógica. En lugar de una red social de exposición única, propone un sistema donde el formato, la duración y la audiencia se ajustan a cada situación.",
            top: 46
        )

        fill(CGRect(x: 42, y: 170, width: 246, height: 98), color: Palette.panel, radius: 22)
        stroke(CGRect(x: 42, y: 170, width: 246, height: 98), color: Palette.line, radius: 22)
        _ = text("Momentos", x: 60, y: 188, width: 180, font: Font.semibold(18), color: Palette.dark)
        _ = text("Publicaciones de foto y vídeo con ubicación, etiquetas, colecciones y controles de interacción.", x: 60, y: 216, width: 205, font: Font.regular(13), color: Palette.ink, lineHeight: 18)

        fill(CGRect(x: 307, y: 170, width: 246, height: 98), color: Palette.panel, radius: 22)
        stroke(CGRect(x: 307, y: 170, width: 246, height: 98), color: Palette.line, radius: 22)
        _ = text("Historias", x: 325, y: 188, width: 180, font: Font.semibold(18), color: Palette.dark)
        _ = text("Contenido efímero, creativo y más expresivo, con stickers, respuestas, enlaces y herramientas de publicación rápida.", x: 325, y: 216, width: 205, font: Font.regular(13), color: Palette.ink, lineHeight: 18)

        placeImage(path: assets.feed, in: CGRect(x: 42, y: 292, width: 250, height: 470), radius: 26)
        placeImage(path: assets.creator, in: CGRect(x: 303, y: 292, width: 250, height: 470), radius: 26)

        _ = text("Feed social y visual", x: 78, y: 730, width: 180, font: Font.semibold(14), color: Palette.dark)
        _ = text("Selector de formato", x: 353, y: 730, width: 160, font: Font.semibold(14), color: Palette.dark)
    }

    private func drawPrivacyPage() {
        fill(CGRect(x: 0, y: 0, width: width, height: height), color: Palette.bg)
        titleBlock(
            eyebrow: "02 · Privacidad y control",
            title: "La diferencia no es tener stories: es cómo se organizan las audiencias",
            body: "Moments se desmarca del modelo binario público/privado. Introduce mejores amigos, listas personalizadas, selección manual y controles finos sobre followers, following y conexiones mutuas.",
            top: 46
        )

        placeImage(path: assets.audience, in: CGRect(x: 42, y: 210, width: 255, height: 560), radius: 26)
        placeImage(path: assets.privacy, in: CGRect(x: 300, y: 210, width: 253, height: 560), radius: 26)

        fill(CGRect(x: 42, y: 160, width: 511, height: 34), color: Palette.soft, radius: 17)
        centeredText("Privacidad modular, no binaria", rect: CGRect(x: 46, y: 168, width: 503, height: 18), font: Font.semibold(12), color: Palette.muted)

        _ = text("Esto permite una idea de red social menos rígida: el usuario no decide solo si publica o no, sino para quién, bajo qué reglas y con cuánta visibilidad permanece cada pieza.", x: 42, y: 780, width: 500, font: Font.regular(13.5), color: Palette.ink, lineHeight: 20)
    }

    private func drawEchoPage() {
        fill(CGRect(x: 0, y: 0, width: width, height: height), color: Palette.bg)
        titleBlock(
            eyebrow: "03 · Función diferencial",
            title: "Echo: una experiencia social propia de Moments",
            body: "Echo combina lugar, tiempo y relación entre participantes. Cuando varias personas cercanas comparten el mismo instante, puede generarse una experiencia colaborativa con distintas perspectivas del mismo momento.",
            top: 46
        )

        fill(CGRect(x: 42, y: 170, width: 511, height: 100), color: Palette.dark, radius: 24)
        let gradient = NSGradient(colors: [Palette.blue, Palette.pink, Palette.gold])!
        let gradientPath = NSBezierPath(roundedRect: CGRect(x: 42, y: 170, width: 511, height: 100), xRadius: 24, yRadius: 24)
        gradient.draw(in: gradientPath, angle: 0)
        fill(CGRect(x: 43, y: 171, width: 509, height: 98), color: Palette.dark.withAlphaComponent(0.82), radius: 23)
        _ = text("Echo no es una reacción ni un filtro. Es un formato nuevo: varias perspectivas del mismo instante, activadas por cercanía y contexto.", x: 62, y: 198, width: 460, font: Font.medium(18), color: NSColor.white, lineHeight: 26)

        placeImage(path: assets.echoes, in: CGRect(x: 42, y: 298, width: 220, height: 454), radius: 26, background: Palette.dark)
        placeImage(path: assets.maps, in: CGRect(x: 280, y: 298, width: 273, height: 454), radius: 26, background: Palette.dark)

        _ = text("Gestión de Echoes", x: 88, y: 720, width: 150, font: Font.semibold(14), color: Palette.dark)
        _ = text("Mapa y contexto geográfico", x: 336, y: 720, width: 190, font: Font.semibold(14), color: Palette.dark)

        fill(CGRect(x: 42, y: 770, width: 511, height: 42), color: Palette.panel, radius: 18)
        stroke(CGRect(x: 42, y: 770, width: 511, height: 42), color: Palette.line, radius: 18)
        centeredText("Echo abre un ángulo editorial claro: la red social como experiencia compartida, no solo como publicación individual.", rect: CGRect(x: 58, y: 782, width: 479, height: 16), font: Font.medium(12), color: Palette.muted)
    }

    private func drawComparisonPage() {
        fill(CGRect(x: 0, y: 0, width: width, height: height), color: Palette.bg)
        titleBlock(
            eyebrow: "04 · Posicionamiento",
            title: "Dónde se diferencia de otras plataformas sociales",
            body: "Moments no intenta ganar a gigantes por volumen. Su propuesta es otra: menos todo-para-todos, más audiencias ajustadas, más memoria del contenido y una capa colaborativa propia.",
            top: 46
        )

        let tableX: CGFloat = 42
        let tableY: CGFloat = 176
        let tableW: CGFloat = 511
        let col1: CGFloat = 92
        let col2: CGFloat = 126
        let col3: CGFloat = 126
        let col4: CGFloat = tableW - col1 - col2 - col3
        let headerH: CGFloat = 38
        let rowH: CGFloat = 88
        fill(CGRect(x: tableX, y: tableY, width: tableW, height: headerH + rowH * 4), color: Palette.panel, radius: 20)
        stroke(CGRect(x: tableX, y: tableY, width: tableW, height: headerH + rowH * 4), color: Palette.line, radius: 20)
        fill(CGRect(x: tableX, y: tableY, width: tableW, height: headerH), color: Palette.soft, radius: 20)
        _ = text("Red", x: tableX + 12, y: tableY + 12, width: col1 - 18, font: Font.semibold(10), color: Palette.muted)
        _ = text("Lógica principal", x: tableX + col1 + 12, y: tableY + 12, width: col2 - 18, font: Font.semibold(10), color: Palette.muted)
        _ = text("Límite típico", x: tableX + col1 + col2 + 12, y: tableY + 12, width: col3 - 18, font: Font.semibold(10), color: Palette.muted)
        _ = text("Respuesta de Moments", x: tableX + col1 + col2 + col3 + 12, y: tableY + 12, width: col4 - 18, font: Font.semibold(10), color: Palette.muted)

        let rows: [(String, String, String, String)] = [
            ("Instagram", "Perfil visual, stories y alcance.", "Muy fuerte en visibilidad, menos en audiencias modulares.", "Más foco en contexto y reglas de relación."),
            ("TikTok", "Descubrimiento algorítmico y entretenimiento.", "Excelente para alcance, menos para vínculo relacional.", "Más control social y menos dependencia del feed masivo."),
            ("BeReal", "Ritual social muy concreto.", "Una sola dinámica, poca elasticidad.", "Más formatos y más capacidad de ajuste."),
            ("Snapchat", "Comunicación visual efímera.", "Gran intimidad, menos memoria organizada.", "Une efímero, perfil, archivo y colaboración.")
        ]

        for (i, row) in rows.enumerated() {
            let y = tableY + headerH + CGFloat(i) * rowH
            if i > 0 {
                fill(CGRect(x: tableX + 1, y: y, width: tableW - 2, height: 1), color: Palette.line)
            }
            let cols = [col1, col2, col3, col4]
            var x = tableX
            for (idx, value) in [row.0, row.1, row.2, row.3].enumerated() {
                let inset: CGFloat = 12
                let font = idx == 0 ? Font.semibold(13) : Font.regular(12)
                _ = text(value, x: x + inset, y: y + 12, width: cols[idx] - inset * 2, font: font, color: Palette.ink, lineHeight: 17)
                x += cols[idx]
            }
        }

        fill(CGRect(x: 42, y: 592, width: 511, height: 170), color: Palette.panel, radius: 24)
        stroke(CGRect(x: 42, y: 592, width: 511, height: 170), color: Palette.line, radius: 24)
        _ = text("Por qué puede interesar a televisión", x: 62, y: 618, width: 280, font: Font.semibold(18), color: Palette.dark)
        let bullets = [
            "Una red social independiente con tesis propia, no solo con diseño distinto.",
            "Una historia clara sobre fatiga social, privacidad y nuevos formatos.",
            "Echo ofrece una demo visual fuerte y fácil de explicar en pantalla.",
            "El producto sugiere una conversación más amplia: cómo deberían evolucionar las redes sociales."
        ]
        var bulletY: CGFloat = 650
        for bullet in bullets {
            fill(CGRect(x: 64, y: bulletY + 5, width: 6, height: 6), color: Palette.blue, radius: 3)
            _ = text(bullet, x: 78, y: bulletY, width: 445, font: Font.regular(13), color: Palette.ink, lineHeight: 19)
            bulletY += 28
        }

        _ = text("Moments · dossier editorial preparado para outreach a medios", x: 42, y: 795, width: 300, font: Font.regular(11), color: Palette.muted)
    }
}

let outputPath = ProcessInfo.processInfo.environment["OUTPUT_PDF_PATH"]
    ?? "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/docs/marketing/Moments_Dossier_Medios_ES.pdf"
let outputURL = URL(fileURLWithPath: outputPath)

do {
    try PDFRenderer(outputURL: outputURL).render()
    print(outputPath)
} catch {
    fputs("Error generating PDF: \(error)\n", stderr)
    exit(1)
}
