import SwiftUI

struct MessageComposerView: View {
    let selectedUser: AppUser?
    @Binding var messageText: String
    let onSend: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "007AFF").opacity(0.1), Color(hex: "02C39A").opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    if let user = selectedUser {
                        VStack(spacing: 12) {
                            AsyncProfileImageView(userId: user.id)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())

                            Text(user.username)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(adaptiveColors.primary)

                            Text("messaging.writeMessageToStart")
                                .font(.body)
                                .foregroundColor(adaptiveColors.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    }

                    Spacer()

                    VStack(spacing: 16) {
                        TextField(NSLocalizedString("messaging.compose.placeholder", comment: "Message composer placeholder"), text: $messageText, axis: .vertical)
                            .font(.body)
                            .foregroundColor(adaptiveColors.primary)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(adaptiveColors.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(adaptiveColors.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .lineLimit(3...6)

                        Button(action: {
                            onSend()
                        }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("messaging.sendMessage")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                          adaptiveColors.secondary : Color(hex: "007AFF"))
                            )
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(NSLocalizedString("messaging.compose.title", comment: "New message title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct OnlineStatusSelectorView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let currentStatus: OnlineStatus
    let onStatusSelected: (OnlineStatus) -> Void

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("messaging.status.current", comment: "Current status"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(adaptiveColors.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(currentStatus.color)

                        Text(currentStatus.displayName)
                            .font(.custom("Poppins-Bold", size: 24))
                            .foregroundColor(adaptiveColors.primary)
                    }
                }
                .padding(.top, 20)

                VStack(spacing: 0) {
                    ForEach(Array(OnlineStatus.allCases.enumerated()), id: \.element) { index, status in
                        Button(action: {
                            onStatusSelected(status)
                            dismiss()
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: status.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(status.color)
                                    .frame(width: 24)

                                Text(status.displayName)
                                    .font(.custom("Poppins-Regular", size: 16))
                                    .foregroundColor(adaptiveColors.primary)

                                Spacer()

                                if status == currentStatus {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(adaptiveColors.accent)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                (colorScheme == .dark ? Color.white : Color.black)
                                    .opacity(status == currentStatus ? 0.06 : 0)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        if index < OnlineStatus.allCases.count - 1 {
                            Divider()
                                .overlay(
                                    (colorScheme == .dark ? Color.white : Color.black)
                                        .opacity(0.08)
                                )
                                .padding(.leading, 64)
                                .padding(.trailing, 20)
                        }
                    }
                }
                .padding(.top, 4)

                Spacer(minLength: 20)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
