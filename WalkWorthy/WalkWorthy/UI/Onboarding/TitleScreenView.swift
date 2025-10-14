//
//  TitleScreenView.swift
//  WalkWorthy
//
//  Presents the branded welcome experience before authentication.
//

import SwiftUI

struct TitleScreenView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSigningIn = false
    @State private var signInError: String?

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)

                VStack(spacing: 16) {
                    Text("For when life seems like rough waters, WalkWorthy knowing God is with you through the storm.")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)

                    Text("Tap continue to sign in with your WalkWorthy account.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    if let notice = appState.authenticationNotice {
                        Text(notice)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                Button(action: startSignIn) {
                    HStack {
                        if isSigningIn {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Continue →")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.vertical, 48)
        }
        .alert("Sign-in failed", isPresented: Binding(
            get: { signInError != nil },
            set: { newValue in if !newValue { signInError = nil } }
        )) {
            Button("OK", role: .cancel) { signInError = nil }
        } message: {
            Text(signInError ?? "")
        }
    }

    private var logoImage: Image {
        Image(colorScheme == .dark ? "TitleLogoDark" : "TitleLogoLight")
            .renderingMode(.original)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ?
                [Color(hex: 0x031E52), Color(hex: 0x012859), Color(hex: 0x0A3E7C)] :
                [Color(hex: 0xA9D7FF), Color(hex: 0x6DB6FF), Color(hex: 0x3384FF)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func startSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true

        Task {
            do {
                try await appState.startSignIn(anchor: nil)
            } catch {
                signInError = error.localizedDescription
            }
            await MainActor.run {
                isSigningIn = false
            }
        }
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
