import SwiftUI

enum HighlightSheet: Identifiable {
    case create
    case edit(HighlightedStory)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let highlight):
            return "edit-\(highlight.id ?? UUID().uuidString)"
        }
    }
}

@Observable
final class HighlightPresentationCoordinator {
    var sheet: HighlightSheet?
    var viewerHighlight: HighlightedStory?

    var isSheetPresented: Bool {
        sheet != nil
    }

    var isViewerPresented: Bool {
        viewerHighlight != nil
    }

    func presentCreate() {
        viewerHighlight = nil
        sheet = .create
    }

    func presentEdit(_ highlight: HighlightedStory) {
        viewerHighlight = nil
        sheet = .edit(highlight)
    }

    func presentViewer(_ highlight: HighlightedStory) {
        if sheet != nil || viewerHighlight != nil {
            sheet = nil
            viewerHighlight = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + MapSheetPresentationDelay.dismissBeforeNextPresentation) {
                self.viewerHighlight = highlight
            }
        } else {
            viewerHighlight = highlight
        }
    }

    func dismissSheet() {
        sheet = nil
    }

    func dismissViewer() {
        viewerHighlight = nil
    }

    func closeAll() {
        sheet = nil
        viewerHighlight = nil
    }
}

struct HighlightGlassSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.clear)
    }
}

extension View {
    func highlightGlassSheet() -> some View {
        modifier(HighlightGlassSheetModifier())
    }
}

extension HighlightedStory: Hashable {
    static func == (lhs: HighlightedStory, rhs: HighlightedStory) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
