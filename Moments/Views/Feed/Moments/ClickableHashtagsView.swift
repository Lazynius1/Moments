import SwiftUI
import Foundation

struct ClickableHashtagsView: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(groupWordsInLines(), id: \.id) { line in
                HStack(spacing: 0) {
                    ForEach(line.words, id: \.id) { word in
                        if word.content.hasPrefix("#") && word.content.count > 1 {
                            Button(action: {
                                let hashtag = String(word.content.dropFirst())
                                onHashtagTap(hashtag)
                            }) {
                                Text(word.content)
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                    .foregroundColor(Color(hex: "667eea"))
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Text(word.content)
                                .font(.system(size: legacyPoppinsSize(14)))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.95) : .black.opacity(0.9))
                        }
                    }
                    Spacer()
                }
            }
        }
    }
    
    private func groupWordsInLines() -> [WordLine] {
        let parts = parseContentForHashtags(content)
        var lines: [WordLine] = []
        var currentWords: [WordItem] = []
        
        for part in parts {
            if part.content == "\n" {
                if !currentWords.isEmpty {
                    lines.append(WordLine(words: currentWords))
                    currentWords = []
                }
            } else {
                currentWords.append(WordItem(content: part.content))
            }
        }
        
        if !currentWords.isEmpty {
            lines.append(WordLine(words: currentWords))
        }
        
        return lines.isEmpty ? [WordLine(words: [WordItem(content: content)])] : lines
    }
}

struct ClickableHashtagsHStackView: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    
    private var contentParts: [ContentPart] {
        parseContentForHashtags(content)
    }
    
    var body: some View {
        FeedFlowLayout(contentParts, spacing: 4) { part in
            switch part.type {
            case .text:
                Text(part.content)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.95) : .black.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            
            case .hashtag:
                Button(action: {
                    let hashtag = String(part.content.dropFirst())
                    onHashtagTap(hashtag)
                }) {
                    Text(part.content)
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundColor(Color(hex: "667eea"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(hex: "667eea").opacity(0.1))
                                .overlay(
                                    Capsule()
                                        .stroke(Color(hex: "667eea").opacity(0.3), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct ContentPart: Identifiable {
    let id = UUID()
    let content: String
    let type: ContentType
    
    enum ContentType {
        case text
        case hashtag
    }
}

struct WordLine: Identifiable {
    let id = UUID()
    let words: [WordItem]
}

struct WordItem: Identifiable {
    let id = UUID()
    let content: String
}

func parseContentForHashtags(_ content: String) -> [ContentPart] {
    var parts: [ContentPart] = []
    let words = content.components(separatedBy: .whitespacesAndNewlines)
    
    for (index, word) in words.enumerated() {
        if word.hasPrefix("#") && word.count > 1 {
            parts.append(ContentPart(content: word, type: .hashtag))
        } else {
            parts.append(ContentPart(content: word, type: .text))
        }
        
        if index < words.count - 1 {
            parts.append(ContentPart(content: " ", type: .text))
        }
    }
    
    return parts
}

struct FeedFlowLayout: View {
    let spacing: CGFloat
    let content: () -> [AnyView]
    
    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> [AnyView]) {
        self.spacing = spacing
        self.content = content
    }
    
    init<Data, Content>(
        _ data: Data,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) where Data: RandomAccessCollection, Content: View {
        self.spacing = spacing
        self.content = {
            data.map { AnyView(content($0)) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            let views = content()
            
            ForEach(0..<views.count, id: \.self) { index in
                views[index]
            }
        }
    }
}
