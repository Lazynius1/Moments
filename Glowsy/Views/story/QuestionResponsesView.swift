import SwiftUI
import FirebaseFirestore

// MARK: - Questions Received Flow (Author)
struct QuestionResponsesView: View {
    let questionText: String
    let storyId: String
    let userId: String

    @Environment(\.dismiss) private var dismiss
    @State private var responses: [QuestionResponse] = []
    @State private var isLoading = true
    @State private var selectedResponse: QuestionResponse?
    @State private var showingCreatorView = false

    private var isDetailFlow: Bool {
        selectedResponse != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Group {
                if let selectedResponse {
                    shareQuestionFlow(response: selectedResponse)
                } else {
                    receivedQuestionsFlow
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showingCreatorView) {
            if let selectedResponse {
                CreatorViewWithResponseData(
                    questionText: questionText,
                    response: selectedResponse,
                    onDismiss: {
                        showingCreatorView = false
                        dismiss()
                    }
                )
            }
        }
        .onAppear {
            loadResponses()
        }
    }

    private var sheetHeader: some View {
        HStack {
            Button(action: {
                if isDetailFlow {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selectedResponse = nil
                    }
                } else {
                    dismiss()
                }
            }) {
                Image(systemName: isDetailFlow ? "chevron.left" : "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background {
                        Color.clear
                            .liquidGlass(in: Circle(), interactive: true)
                    }
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var receivedQuestionsFlow: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("questionResponses.title", comment: "Questions received title"))
                    .font(.custom("Poppins-SemiBold", size: 24))
                    .foregroundStyle(.primary)

                Text(NSLocalizedString("questionResponses.subtitle", comment: "Questions received subtitle"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            Text(questionText)
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 20)

            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(NSLocalizedString("questionResponses.loading", comment: "Loading questions"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if responses.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.bubble")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(NSLocalizedString("questionResponses.emptyTitle", comment: "No questions yet"))
                            .font(.custom("Poppins-SemiBold", size: 17))
                            .foregroundStyle(.primary)

                        Text(NSLocalizedString("questionResponses.emptySubtitle", comment: "Share story to receive questions"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 32)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(responses.enumerated()), id: \.element.id) { index, response in
                                QuestionResponseRow(
                                    response: response,
                                    onShare: {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                            selectedResponse = response
                                        }
                                    }
                                )
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)

                                if index < responses.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func shareQuestionFlow(response: QuestionResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("questionResponses.shareResponse", comment: "Respond in story title"))
                    .font(.custom("Poppins-SemiBold", size: 24))
                    .foregroundStyle(.primary)

                Text(NSLocalizedString("questionResponses.shareSubtitle", comment: "Respond in story subtitle"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            promptCard(questionText: questionText)
                .padding(.horizontal, 20)

            responsePreviewCard(response: response)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)

            Button(action: {
                showingCreatorView = true
            }) {
                Text(NSLocalizedString("questionResponses.createStory", comment: "Reply in your story button"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                    }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func promptCard(questionText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("questionResponses.promptLabel", comment: "Prompt label"), systemImage: "questionmark.bubble.fill")
                .font(.custom("Poppins-SemiBold", size: 13))
                .foregroundStyle(.secondary)

            Text(questionText)
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func responsePreviewCard(response: QuestionResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("questionResponses.questionLabel", comment: "Question label"))
                .font(.custom("Poppins-SemiBold", size: 13))
                .foregroundStyle(.secondary)

            Text(response.response)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func loadResponses() {
        let db = Firestore.firestore()
        db.collection("users").document(userId).collection("stories").document(storyId)
            .collection("questionResponses")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    isLoading = false
                    if let documents = snapshot?.documents {
                        self.responses = documents.compactMap { document in
                            let data = document.data()
                            return QuestionResponse(
                                userId: data["userId"] as? String ?? "",
                                response: data["response"] as? String ?? ""
                            )
                        }
                    }
                }
            }
    }
}

private struct QuestionResponseRow: View {
    let response: QuestionResponse
    let onShare: () -> Void

    @State private var responderUsername: String = ""
    @State private var showingResponderProfile = false

    var body: some View {
        Button(action: onShare) {
            HStack(alignment: .top, spacing: 12) {
                AsyncProfileImageView(userId: response.userId)
                    .frame(width: 38, height: 38)
                    .onTapGesture {
                        showingResponderProfile = true
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(responderUsername.isEmpty ? NSLocalizedString("common.loading", comment: "Loading") : responderUsername)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundStyle(.primary)

                        Text(timeAgo(from: response.timestamp))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text(response.response)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background {
                        Color.clear
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingResponderProfile) {
            UserProfileView(userId: response.userId)
        }
        .onAppear {
            loadResponderUsername()
        }
    }

    private func loadResponderUsername() {
        FirestoreService().db.collection("users").document(response.userId).getDocument { document, _ in
            DispatchQueue.main.async {
                if let document,
                   document.exists,
                   let data = document.data(),
                   let username = data["username"] as? String {
                    self.responderUsername = username
                }
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CreatorViewWithResponseData: View {
    let questionText: String
    let response: QuestionResponse
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingStory: Bool = true
    @State private var showCreatorView: Bool = true

    var body: some View {
        CreatorView(
            isCreatingStory: $isCreatingStory,
            showCreatorView: $showCreatorView,
            initialSticker: createResponseStickerImage(),
            startInCameraWhenOnlySticker: true
        )
        .onChange(of: showCreatorView) { _, newValue in
            if !newValue {
                onDismiss()
            }
        }
    }

    private func createResponseStickerImage() -> StickerItem {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 60))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 200, height: 60)

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.systemBlue.cgColor,
                    UIColor.systemPurple.cgColor,
                    UIColor.systemPink.cgColor
                ] as CFArray,
                locations: [0.0, 0.5, 1.0]
            )!

            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 200, y: 60),
                options: []
            )

            let borderPath = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            borderPath.lineWidth = 2
            UIColor.white.withAlphaComponent(0.3).setStroke()
            borderPath.stroke()

            let iconRect = CGRect(x: 12, y: 10, width: 18, height: 18)
            let iconPath = UIBezierPath(ovalIn: iconRect)
            UIColor.white.setFill()
            iconPath.fill()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Poppins-SemiBold", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.white
            ]

            let titleString = NSLocalizedString("questionResponses.anonymousResponseTitle", comment: "Anonymous question title")
            titleString.draw(
                at: CGPoint(x: 35, y: 12),
                withAttributes: titleAttributes
            )

            let responseAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Poppins-Regular", size: 12) ?? UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.white
            ]

            let responseString = response.response
            let responseRect = CGRect(x: 12, y: 32, width: 176, height: 24)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.alignment = .center

            var finalAttributes = responseAttributes
            finalAttributes[.paragraphStyle] = paragraphStyle

            responseString.draw(
                with: responseRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: finalAttributes,
                context: nil
            )
        }

        return StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .questionResponse,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: "Pregunta: \(response.response)",
                weatherSymbol: nil,
                caption: nil,
                profileImagePath: nil,
                momentId: nil
            )
        )
    }
}
