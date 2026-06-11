import SwiftUI
import Kingfisher

struct HighlightNameCoverStep: View {
    @Bindable var viewModel: HighlightCreateFlowViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTitleFocused: Bool

    private let coverSize: CGFloat = 118

    private var coverURL: String? {
        viewModel.coverStory?.mediaItem.thumbnailUrl
            ?? viewModel.coverStory?.mediaItem.url
            ?? viewModel.editingHighlight?.coverImageUrl
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                AppErrorBanner(message: errorMessage) {
                    viewModel.errorMessage = nil
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            Spacer(minLength: 32)

            VStack(spacing: 14) {
                Button {
                    viewModel.showCoverPicker = true
                } label: {
                    coverPreview
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.showCoverPicker = true
                } label: {
                    Text(NSLocalizedString("highlightedStories.editCover", comment: ""))
                        .font(.custom("Poppins-Medium", size: 15))
                        .foregroundColor(ProfileColors.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 40)

            TextField(
                "",
                text: $viewModel.title,
                prompt: Text(NSLocalizedString("highlightedStories.defaultTitle", comment: ""))
                    .foregroundColor(ProfileColors.textSecondary)
            )
            .font(.custom("Poppins-Medium", size: 16))
            .foregroundColor(ProfileColors.textPrimary)
            .multilineTextAlignment(.center)
            .focused($isTitleFocused)
            .submitLabel(.done)
            .padding(.horizontal, 48)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isTitleFocused = true
            }
        }
        .sheet(isPresented: $viewModel.showCoverPicker) {
            HighlightCoverPickerSheet(
                stories: viewModel.selectedStories,
                selectedCoverId: viewModel.coverStory?.id,
                onSelect: { viewModel.coverStory = $0 }
            )
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        ZStack {
            if let coverURL, let url = URL(string: coverURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: coverSize, height: coverSize)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: coverSize, height: coverSize)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary.opacity(0.5))
                    )
            }
        }
    }
}
