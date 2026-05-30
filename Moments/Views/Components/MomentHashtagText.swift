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
    let mentionFont: Font
    let baseColor: Color
    let hashtagColor: Color
    let mentionColor: Color
    let textAlignment: TextAlignment
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowX: CGFloat
    let shadowY: CGFloat
    let lineLimit: Int?
    let onHashtagTap: (String) -> Void
    let onMentionTap: ((String) -> Void)?

    init(
        content: String,
        textFont: Font,
        hashtagFont: Font,
        mentionFont: Font? = nil,
        baseColor: Color,
        hashtagColor: Color = MomentHashtagParser.hashtagColor,
        mentionColor: Color = MomentMentionParser.mentionColor,
        textAlignment: TextAlignment = .leading,
        shadowColor: Color = .clear,
        shadowRadius: CGFloat = 0,
        shadowX: CGFloat = 0,
        shadowY: CGFloat = 0,
        lineLimit: Int? = nil,
        onHashtagTap: @escaping (String) -> Void,
        onMentionTap: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.textFont = textFont
        self.hashtagFont = hashtagFont
        self.mentionFont = mentionFont ?? hashtagFont
        self.baseColor = baseColor
        self.hashtagColor = hashtagColor
        self.mentionColor = mentionColor
        self.textAlignment = textAlignment
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowX = shadowX
        self.shadowY = shadowY
        self.lineLimit = lineLimit
        self.onHashtagTap = onHashtagTap
        self.onMentionTap = onMentionTap
    }

    var body: some View {
        Text(buildAttributedString())
            .font(textFont)
            .multilineTextAlignment(textAlignment)
            .lineLimit(lineLimit)
            .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
            .environment(\.openURL, OpenURLAction { url in
                if let hashtag = MomentHashtagLink.hashtag(from: url) {
                    onHashtagTap(hashtag)
                    return .handled
                }

                if let username = MomentMentionLink.username(from: url) {
                    onMentionTap?(username)
                    return .handled
                }

                return .systemAction
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

        for match in MomentMentionParser.matches(in: content).reversed() {
            guard let attributedRange = match.range.toAttributedStringRange(in: attributed) else {
                continue
            }

            attributed[attributedRange].foregroundColor = mentionColor
            attributed[attributedRange].font = mentionFont
            if onMentionTap != nil {
                attributed[attributedRange].link = MomentMentionLink.url(for: match.username)
            }
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
