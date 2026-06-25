import SwiftUI

struct HighlightCreateFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: HighlightCreateFlowViewModel
    @State private var showDeleteConfirmation = false

    init(mode: HighlightFlowMode) {
        _viewModel = State(initialValue: HighlightCreateFlowViewModel(mode: mode))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ZStack {
                HighlightFlowBackground()

                switch viewModel.step {
                case .selectStories:
                    HighlightSelectStoriesStep(viewModel: viewModel)
                case .nameAndCover:
                    HighlightNameCoverStep(viewModel: viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent(viewModel: viewModel) }
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .confirmationDialog(
            NSLocalizedString("common.delete", comment: ""),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                viewModel.deleteHighlight { error in
                    if error == nil {
                        dismiss()
                    }
                }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(viewModel: HighlightCreateFlowViewModel) -> some ToolbarContent {
        switch viewModel.step {
        case .selectStories:
            ToolbarItem(placement: .topBarLeading) {
                Button(NSLocalizedString("common.cancel", comment: "")) {
                    dismiss()
                }
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundColor(ProfileColors.textPrimary)
            }

            ToolbarItem(placement: .principal) {
                Text(navigationTitle(for: viewModel))
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(ProfileColors.textPrimary)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.advanceToNameAndCover()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(viewModel.canAdvance ? ProfileColors.accent : .secondary)
                }
                .disabled(!viewModel.canAdvance)
            }

        case .nameAndCover:
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.backToSelectStories()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(ProfileColors.textPrimary)
                }
            }

            ToolbarItem(placement: .principal) {
                Text(nameCoverNavigationTitle(for: viewModel))
                    .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                    .foregroundColor(ProfileColors.textPrimary)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.isEditMode {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(ProfileColors.textPrimary)
                    }
                }

                Button {
                    viewModel.save { error in
                        if error == nil {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: viewModel.isEditMode ? "checkmark" : "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(viewModel.canSave ? ProfileColors.accent : .secondary)
                    }
                }
                .disabled(!viewModel.canSave || viewModel.isSaving)
            }
        }
    }

    private func navigationTitle(for viewModel: HighlightCreateFlowViewModel) -> String {
        NSLocalizedString("highlightedStories.addToHighlights", comment: "")
    }

    private func nameCoverNavigationTitle(for viewModel: HighlightCreateFlowViewModel) -> String {
        if viewModel.isEditMode {
            return NSLocalizedString("highlightedStories.editHighlightTitle", comment: "")
        }
        return NSLocalizedString("highlightedStories.newHighlightTitle", comment: "")
    }
}

struct HighlightFlowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .ignoresSafeArea()
    }
}
