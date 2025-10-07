//
//  HistoryView.swift
//  WalkWorthy
//
//  Shows recently viewed verses.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.history.isEmpty {
                    emptyState
                } else {
                    List(appState.history) { verse in
                        NavigationLink(value: verse) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verse.reference)
                                    .font(.headline)
                                Text(verse.encouragement)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !appState.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) {
                            withAnimation(.easeInOut) {
                                appState.clearHistory()
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: Verse.self) { verse in
                VerseDetailView(verse: verse)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("History will appear here once you explore verses.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct VerseDetailView: View {
    let verse: Verse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VerseCard(verse: verse, selectedTranslation: verse.translation)
                Text("Encouragement")
                    .font(.headline)
                Text(verse.encouragement)
                    .font(.body)
                Text("Translation: \(verse.translation.displayName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle(verse.reference)
        .toolbarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
