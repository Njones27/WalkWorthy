//
//  CanvasLinkView.swift
//  WalkWorthy
//
//  Mock Canvas connection toggle for UI testing.
//

import SwiftUI
import UIKit

struct CanvasLinkView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: appState.isCanvasLinked ? "checkmark.circle.fill" : "link")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(appState.isCanvasLinked ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.isCanvasLinked ? "Canvas linked (mock)" : "Link Canvas (mock)")
                        .font(.headline)
                    Text(appState.isCanvasLinked ? "We’ll surface assignments in encouragements." : "Tap to simulate a Canvas OAuth flow. No credentials needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button(action: toggle) {
                Text(appState.isCanvasLinked ? "Unlink Canvas" : "Link Canvas (Mock)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(!appState.useFakeCanvas)
            .opacity(appState.useFakeCanvas ? 1 : 0.5)

            if let summary = appState.canvasSummary, appState.isCanvasLinked {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today in Canvas")
                        .font(.subheadline.bold())
                    if summary.assignmentsToday.isEmpty && summary.examsToday.isEmpty {
                        Text("You’re all caught up! 🎉")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !summary.assignmentsToday.isEmpty {
                        ForEach(summary.assignmentsToday) { assignment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assignment.title)
                                    .font(.callout.weight(.semibold))
                                Text("Due: \(assignment.dueAt.formattedCanvasDate())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !summary.examsToday.isEmpty {
                        ForEach(summary.examsToday) { exam in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exam.title)
                                    .font(.callout.weight(.semibold))
                                Text(exam.when)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .glassCard()
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appState.isCanvasLinked)
    }

    private func toggle() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            appState.toggleCanvasLink()
            if appState.isCanvasLinked {
                appState.refreshCanvasSummary()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

private extension String {
    func formattedCanvasDate() -> String {
        guard let date = ISO8601DateFormatter().date(from: self) else { return self }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
