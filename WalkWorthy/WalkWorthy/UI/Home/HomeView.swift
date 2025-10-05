//
//  HomeView.swift
//  WalkWorthy
//
//  Primary verse feed with navigation controls.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                translationMenu

                VerseCard(verse: appState.currentVerse, selectedTranslation: appState.selectedTranslation)

                controlButtons

                CanvasLinkView()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 120)
        }
        .background(backgroundGradient)
        .navigationTitle("Today’s Encouragement")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $appState.showPopups) {
            EncouragementPopupsView(cards: MockData.encouragementCards) {
                appState.dismissPopups()
            }
        }
    }

    private var translationMenu: some View {
        HStack {
            Menu {
                ForEach(Translation.allCases) { translation in
                    Button {
                        appState.setTranslation(translation)
                    } label: {
                        if translation == appState.selectedTranslation {
                            Label(translation.displayName, systemImage: "checkmark")
                        } else {
                            Text(translation.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Translation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(appState.selectedTranslation.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }

            Spacer()
        }
    }

    private var controlButtons: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button(action: appState.goToPreviousVerse) {
                    Label("Previous", systemImage: "chevron.left")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())

                Button(action: appState.goToNextVerse) {
                    Label("Next", systemImage: "chevron.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
            }

            Button {
                appState.presentPopups()
            } label: {
                Label("Show Pop-ups", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassAccentButtonStyle())
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.systemBlue).opacity(0.1), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.3 : 0.15), lineWidth: 1)
            )
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private struct GlassAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(Color.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 14, x: 0, y: 10)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
