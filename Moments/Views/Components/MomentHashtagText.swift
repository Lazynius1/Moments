import Foundation
import SwiftUI

enum MomentHashtagParser {
    static let hashtagColor = Color(hex: "667eea")

    private static let pattern = #"(?<![\p{L}\p{M}\p{N}_])#([\p{L}\p{M}\p{N}_]+)"#
    private static let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    struct Match {
        let range: Range<String.Index>
        let term: String
    }

    static func matches(in content: String) -> [Match] {
        guard let regex else { return [] }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        return regex.matches(in: content, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range, in: content),
                  let termRange = Range(match.range(at: 1), in: content) else {
                return nil
            }

            return Match(
                range: fullRange,
                term: String(content[termRange])
            )
        }
    }

    static func extractHashtags(from content: String) -> [String] {
        matches(in: content)
            .map(\.term)
            .filter { $0.count > 1 }
    }
}

enum MomentHashtagLink {
    static func url(for hashtag: String) -> URL? {
        var components = URLComponents()
        components.scheme = "hashtag"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "value", value: hashtag)]
        return components.url
    }

    static func hashtag(from url: URL) -> String? {
        guard url.scheme == "hashtag" else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == "value" })?.value,
           !value.isEmpty {
            return value
        }

        return url.host
    }
}

struct MomentHashtagText: View {
    let content: String
    let textFont: Font
    let hashtagFont: Font
    let baseColor: Color
    let hashtagColor: Color
    let textAlignment: TextAlignment
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowX: CGFloat
    let shadowY: CGFloat
    let lineLimit: Int?
    let onHashtagTap: (String) -> Void

    init(
        content: String,
        textFont: Font,
        hashtagFont: Font,
        baseColor: Color,
        hashtagColor: Color = MomentHashtagParser.hashtagColor,
        textAlignment: TextAlignment = .leading,
        shadowColor: Color = .clear,
        shadowRadius: CGFloat = 0,
        shadowX: CGFloat = 0,
        shadowY: CGFloat = 0,
        lineLimit: Int? = nil,
        onHashtagTap: @escaping (String) -> Void
    ) {
        self.content = content
        self.textFont = textFont
        self.hashtagFont = hashtagFont
        self.baseColor = baseColor
        self.hashtagColor = hashtagColor
        self.textAlignment = textAlignment
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowX = shadowX
        self.shadowY = shadowY
        self.lineLimit = lineLimit
        self.onHashtagTap = onHashtagTap
    }

    var body: some View {
        Text(buildAttributedString())
            .font(textFont)
            .multilineTextAlignment(textAlignment)
            .lineLimit(lineLimit)
            .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
            .environment(\.openURL, OpenURLAction { url in
                guard let hashtag = MomentHashtagLink.hashtag(from: url) else {
                    return .systemAction
                }

                onHashtagTap(hashtag)
                return .handled
            })
    }

    private func buildAttributedString() -> AttributedString {
        var attributed = AttributedString(content)
        attributed.foregroundColor = baseColor

        for match in MomentHashtagParser.matches(in: content).reversed() {
            guard let attributedRange = match.range.toAttributedStringRange(in: attributed) else {
                continue
            }

            attributed[attributedRange].foregroundColor = hashtagColor
            attributed[attributedRange].font = hashtagFont
            attributed[attributedRange].link = MomentHashtagLink.url(for: match.term)
        }

        return attributed
    }
}

extension Range where Bound == String.Index {
    func toAttributedStringRange(in attributedString: AttributedString) -> Range<AttributedString.Index>? {
        guard let lowerBound = AttributedString.Index(self.lowerBound, within: attributedString),
              let upperBound = AttributedString.Index(self.upperBound, within: attributedString) else {
            return nil
        }

        return lowerBound..<upperBound
    }
}
