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
                    VStack(spacing: 16) {
                        if let summary = appState.latestScanSummary {
                            summaryCard(summary: summary)
                        } else if let message = appState.encouragementStatusMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        emptyState
                    }
                    .padding()
                } else {
                    List {
                        if let summary = appState.latestScanSummary {
                            Section("Latest Scan") {
                                summaryCard(summary: summary)
                            }
                        }
                        Section("Recent Encouragements") {
                            ForEach(appState.history) { verse in
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

    private func summaryCard(summary: ScanLogSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summary.status == .success ? "Fresh encouragement" : "Fallback encouragement", systemImage: summary.status == .success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(summary.status == .success ? Color.green : Color.orange)

            HStack(spacing: 12) {
                Text("Planner: \(summary.plannerCount ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Stressful: \(summary.stressfulCount ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Candidates: \(summary.candidateCount ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let tags = summary.tags, !tags.isEmpty {
                Text("Tags: \(tags.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = appState.encouragementStatusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
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
