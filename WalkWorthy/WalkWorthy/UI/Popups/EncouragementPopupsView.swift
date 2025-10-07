//
//  EncouragementPopupsView.swift
//  WalkWorthy
//
//  Carousel of encouragement cards with haptics.
//

import SwiftUI
import UIKit

struct EncouragementPopupsView: View {
    let cards: [EncouragementCard]
    var onDismiss: () -> Void

    @State private var index: Int = 0

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $index) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(card.tag.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .tracking(1.2)
                            Text(card.title)
                                .font(.title2.weight(.bold))
                            Text(card.message)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .glassCard()
                        .padding(.horizontal, 24)
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 340)
                .onChange(of: index) { _, _ in
                    impactGenerator.impactOccurred()
                    impactGenerator.prepare()
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground).opacity(0.95))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .navigationTitle("Burst of encouragement")
            .toolbarTitleDisplayMode(.inline)
        }
        .onAppear {
            impactGenerator.prepare()
        }
    }
}
