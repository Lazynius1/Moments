import Foundation
import AppKit
import WebKit

final class HTMLToPDFExporter: NSObject, WKNavigationDelegate {
    private let htmlURL: URL
    private let outputURL: URL
    private let webView: WKWebView
    private let runLoop = RunLoop.current
    private var navigationDone = false
    private var exportDone = false
    private var exportError: Error?
    private var measuredSize = CGSize(width: 794, height: 1123)

    init(htmlURL: URL, outputURL: URL) {
        self.htmlURL = htmlURL
        self.outputURL = outputURL

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    func run() throws {
        guard webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent()) != nil else {
            throw NSError(domain: "HTMLToPDFExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo iniciar la carga del HTML."])
        }

        while !navigationDone {
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if let exportError {
            throw exportError
        }

        Thread.sleep(forTimeInterval: 0.8)

        try measureDocumentSize()
        webView.setFrameSize(measuredSize)

        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(origin: .zero, size: measuredSize)

        webView.createPDF(configuration: configuration) { [weak self] result in
            guard let self else { return }
            do {
                let data = try result.get()
                try data.write(to: self.outputURL)
            } catch {
                self.exportError = error
            }
            self.exportDone = true
        }

        while !exportDone {
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if let exportError {
            throw exportError
        }
    }

    private func measureDocumentSize() throws {
        let widthScript = "Math.max(document.body.scrollWidth, document.documentElement.scrollWidth, 794)"
        let heightScript = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 1123)"
        var widthResult: CGFloat?
        var heightResult: CGFloat?
        var jsDone = false

        webView.evaluateJavaScript(widthScript) { result, error in
            if let error {
                self.exportError = error
                jsDone = true
                return
            }
            if let value = result as? NSNumber {
                widthResult = CGFloat(truncating: value)
            }

            self.webView.evaluateJavaScript(heightScript) { result, error in
                if let error {
                    self.exportError = error
                } else if let value = result as? NSNumber {
                    heightResult = CGFloat(truncating: value)
                }
                jsDone = true
            }
        }

        while !jsDone {
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if let exportError {
            throw exportError
        }

        measuredSize = CGSize(
            width: max(794, widthResult ?? 794),
            height: max(1123, heightResult ?? 1123)
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationDone = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        exportError = error
        navigationDone = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        exportError = error
        navigationDone = true
    }
}

let root = URL(fileURLWithPath: "/Users/lazynius/Desktop/MacMini/Nueva/Glowsy")
let htmlURL = root.appendingPathComponent("docs/marketing/moments_media_dossier_es.html")
let outputURL = root.appendingPathComponent("docs/marketing/Moments_Presentacion_Comercial_ES.pdf")

do {
    try HTMLToPDFExporter(htmlURL: htmlURL, outputURL: outputURL).run()
    print(outputURL.path)
} catch {
    fputs("Error exportando HTML a PDF: \(error.localizedDescription)\n", stderr)
    exit(1)
}
