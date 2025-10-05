//
//  VerseCard.swift
//  WalkWorthy
//
//  Displays the primary verse content with glass styling.
//

import SwiftUI

struct VerseCard: View {
    let verse: Verse
    let selectedTranslation: Translation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verse.reference)
                .font(.title3.weight(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reference: \(verse.reference)")

            Text(verse.text)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .accessibilityLabel("Verse text: \(verse.text)")

            Divider()
                .opacity(0.4)

            Label {
                Text(verse.encouragement)
                    .font(.callout)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Encouragement: \(verse.encouragement)")

            Text("Translation • \(selectedTranslation.rawValue)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .glassCard()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: verse.id)
    }
}
