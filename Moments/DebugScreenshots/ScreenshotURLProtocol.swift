#if DEBUG
import Foundation
import Kingfisher

/// Intercepta peticiones en modo captura: sirve las imágenes de demostración
/// (`moments-screenshots.invalid`) desde el catálogo y rechaza cualquier
/// llamada a los dominios de Google / Firebase.
final class ScreenshotURLProtocol: URLProtocol {
    static func install() {
        URLProtocol.registerClass(ScreenshotURLProtocol.self)

        // Kingfisher usa su propia sesión: hay que añadir el protocolo a mano.
        let configuration = ImageDownloader.default.sessionConfiguration
        var classes = configuration.protocolClasses ?? []
        let ownId = ObjectIdentifier(ScreenshotURLProtocol.self)
        if !classes.contains(where: { ObjectIdentifier($0) == ownId }) {
            classes.insert(ScreenshotURLProtocol.self, at: 0)
        }
        configuration.protocolClasses = classes
        ImageDownloader.default.sessionConfiguration = configuration
    }

    static func isBlockedHost(_ host: String) -> Bool {
        host.hasSuffix("googleapis.com")
            || host.hasSuffix("cloudfunctions.net")
            || host.hasSuffix("firebaseio.com")
            || host.hasSuffix("firebaseapp.com")
            || host.hasSuffix(".run.app")
            || host.contains("firebasestorage")
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return host == ScreenshotImages.host || isBlockedHost(host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              url.host?.lowercased() == ScreenshotImages.host,
              let data = ScreenshotImages.data(for: url),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "image/jpeg",
                    "Content-Length": "\(data.count)"
                ]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
