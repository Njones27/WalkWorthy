//
//  CanvasLinkView.swift
//  WalkWorthy
//
//  Bridges mock and live Canvas linking flows.
//

import SwiftUI
import UIKit

struct CanvasLinkView: View {
    @EnvironmentObject private var appState: AppState
    private let config = Config.shared

    @State private var isLinking = false
    @State private var linkError: String?
    @State private var linkSuccessMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shouldUseLiveFlow {
                liveContent
            } else {
                mockContent
            }
        }
        .glassCard()
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appState.isCanvasLinked)
    }

    private var shouldUseLiveFlow: Bool {
        config.apiMode == "live" && !appState.useFakeCanvas
    }

    // MARK: - Live flow

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: appState.isCanvasLinked ? "checkmark.circle.fill" : "link")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(appState.isCanvasLinked ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.isCanvasLinked ? "Canvas linked" : "Connect Canvas")
                        .font(.headline)
                    Text(liveDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                if let host = config.canvasBaseURL?.host {
                    Text("Domain: \(host)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Status: \(appState.isCanvasLinked ? "Linked" : "Not linked")")
                    .font(.caption)
                    .foregroundStyle(appState.isCanvasLinked ? .green : .secondary)
            }

            if let configIssue = liveConfigurationIssue {
                Text(configIssue)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let message = linkSuccessMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let error = linkError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    startLinkFlow()
                } label: {
                    Label(appState.isCanvasLinked ? "Relink Canvas" : "Link Canvas", systemImage: "link")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(!canAttemptLink)

                if appState.isCanvasLinked {
                    Button(role: .destructive) {
                        unlink()
                    } label: {
                        Label("Unlink", systemImage: "xmark")
                            .font(.subheadline.bold())
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }

            if isLinking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Completing Canvas linking…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var liveDescription: String {
        if !canAttemptLink {
            return "Update your bundle configuration to enable Canvas OAuth."
        }
        return appState.isCanvasLinked ? "You're ready to receive real assignment insights." : "We’ll open Canvas in a secure Safari session to finish linking."
    }

    private var liveConfigurationIssue: String? {
        guard shouldUseLiveFlow else { return nil }
        if config.canvasBaseURL == nil {
            return "Canvas base URL is not configured."
        }
        if config.canvasClientId?.isEmpty ?? true {
            return "Canvas client ID is missing."
        }
        if config.canvasRedirectURI == nil {
            return "Canvas redirect URI is not set."
        }
        return nil
    }

    private var canAttemptLink: Bool {
        !isLinking && liveConfigurationIssue == nil
    }

    private func startLinkFlow() {
        guard canAttemptLink else { return }
        isLinking = true
        linkError = nil
        linkSuccessMessage = nil

        Task {
            do {
                try await appState.startCanvasLink(anchor: nil)
                await MainActor.run {
                    isLinking = false
                    linkSuccessMessage = "Canvas linked successfully."
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    appState.refreshEncouragementDeck()
                }
            } catch {
                await MainActor.run {
                    isLinking = false
                    linkError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func unlink() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            appState.markCanvasUnlinked()
            linkSuccessMessage = "Canvas unlinked."
        }
    }

    // MARK: - Mock flow

    private var mockContent: some View {
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

            Button(action: toggleMockLink) {
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
    }

    private func toggleMockLink() {
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
