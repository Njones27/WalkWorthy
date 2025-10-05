//
//  AppState.swift
//  WalkWorthy
//
//  Created for UI-only sprint.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var verseDeck: [Verse]
    @Published private(set) var history: [Verse]
    @Published private(set) var currentVerseIndex: Int
    @Published var selectedTranslation: Translation
    @Published var showPopups: Bool
    @Published var isCanvasLinked: Bool
    @Published var onboardingCompleted: Bool
    @Published var useProfilePersonalization: Bool
    @Published var useFakeCanvas: Bool
    @Published var canvasSummary: TodayCanvas?

    private let apiClient: any EncouragementAPI
    private let notificationScheduler: NotificationScheduler
    private let defaults: UserDefaults

    init(
        apiClient: any EncouragementAPI = MockAPIClient(),
        notificationScheduler: NotificationScheduler = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.notificationScheduler = notificationScheduler
        self.defaults = defaults

        let config = Config.shared

        onboardingCompleted = defaults.bool(forKey: StorageKey.onboardingCompleted)
        useProfilePersonalization = defaults.object(forKey: StorageKey.useProfilePersonalization) as? Bool ?? true
        useFakeCanvas = defaults.object(forKey: StorageKey.useFakeCanvas) as? Bool ?? config.useFakeCanvas
        isCanvasLinked = defaults.object(forKey: StorageKey.canvasLinked) as? Bool ?? false
        selectedTranslation = Translation(rawValue: defaults.string(forKey: StorageKey.translation) ?? "") ?? config.defaultTranslation
        showPopups = false
        currentVerseIndex = defaults.integer(forKey: StorageKey.currentVerseIndex)
        verseDeck = MockData.verses
        history = (try? defaults.decode([Verse].self, forKey: StorageKey.history)) ?? []
        canvasSummary = try? defaults.decode(TodayCanvas.self, forKey: StorageKey.canvasSummary)

        clampCurrentIndex()
    }

    var currentVerse: Verse {
        verseDeck[safe: currentVerseIndex] ?? MockData.verses.first ?? Verse.placeholder
    }

    func markOnboardingComplete() {
        onboardingCompleted = true
        defaults.set(true, forKey: StorageKey.onboardingCompleted)
    }

    func updateProfile(age: Int?, major: String, gender: Gender, hobbies: Set<String>, optIn: Bool) {
        if let age {
            defaults.set(age, forKey: StorageKey.profileAge)
        } else {
            defaults.removeObject(forKey: StorageKey.profileAge)
        }
        defaults.set(major, forKey: StorageKey.profileMajor)
        defaults.set(gender.rawValue, forKey: StorageKey.profileGender)
        defaults.set(Array(hobbies), forKey: StorageKey.profileHobbies)
        defaults.set(optIn, forKey: StorageKey.profileOptIn)
    }

    func loadProfile() -> OnboardingProfile {
        let age = defaults.value(forKey: StorageKey.profileAge) as? Int
        let major = defaults.string(forKey: StorageKey.profileMajor) ?? ""
        let gender = Gender(rawValue: defaults.string(forKey: StorageKey.profileGender) ?? "") ?? .preferNotToSay
        let hobbies = Set(defaults.stringArray(forKey: StorageKey.profileHobbies) ?? [])
        let optIn = defaults.object(forKey: StorageKey.profileOptIn) as? Bool ?? true
        return OnboardingProfile(age: age, major: major, gender: gender, hobbies: hobbies, optIn: optIn)
    }

    func setUseProfilePersonalization(_ isOn: Bool) {
        useProfilePersonalization = isOn
        defaults.set(isOn, forKey: StorageKey.useProfilePersonalization)
    }

    func setUseFakeCanvas(_ isOn: Bool) {
        useFakeCanvas = isOn
        defaults.set(isOn, forKey: StorageKey.useFakeCanvas)
        if !isOn {
            isCanvasLinked = false
            defaults.set(false, forKey: StorageKey.canvasLinked)
        }
    }

    func setTranslation(_ translation: Translation) {
        selectedTranslation = translation
        defaults.set(translation.rawValue, forKey: StorageKey.translation)
    }

    func toggleCanvasLink() {
        guard useFakeCanvas else { return }
        isCanvasLinked.toggle()
        defaults.set(isCanvasLinked, forKey: StorageKey.canvasLinked)
    }

    func goToNextVerse() {
        guard !verseDeck.isEmpty else { return }
        historyUpsert(currentVerse)
        currentVerseIndex = (currentVerseIndex + 1) % verseDeck.count
        defaults.set(currentVerseIndex, forKey: StorageKey.currentVerseIndex)
    }

    func goToPreviousVerse() {
        guard !verseDeck.isEmpty else { return }
        currentVerseIndex = currentVerseIndex == 0 ? max(verseDeck.count - 1, 0) : currentVerseIndex - 1
        defaults.set(currentVerseIndex, forKey: StorageKey.currentVerseIndex)
    }

    func presentPopups() {
        showPopups = true
    }

    func dismissPopups() {
        showPopups = false
    }

    func scheduleTestNotification() {
        notificationScheduler.scheduleTestNotification()
    }

    func refreshEncouragementDeck() {
        Task {
            do {
                let response = try await apiClient.fetchNext()
                if response.shouldNotify {
                    notificationScheduler.scheduleEncouragementNotification(response.payload)
                }
                if let payload = response.payload {
                    let verse = Verse(payload: payload)
                    await MainActor.run { [verse] in
                        if !verseDeck.contains(where: { $0.id == verse.id }) {
                            verseDeck.insert(verse, at: 0)
                        } else if let index = verseDeck.firstIndex(where: { $0.id == verse.id }) {
                            verseDeck[index] = verse
                        }
                        clampCurrentIndex()
                    }
                }
            } catch {
                print("[AppState] Failed to fetch next encouragement: \(error)")
            }
        }
    }

    func refreshCanvasSummary() {
        guard useFakeCanvas else { return }
        Task {
            do {
                let summary = try await apiClient.fetchTodayCanvas()
                await MainActor.run {
                    canvasSummary = summary
                    try? defaults.encode(summary, forKey: StorageKey.canvasSummary)
                }
            } catch {
                print("[AppState] Failed to fetch canvas summary: \(error)")
            }
        }
    }

    func clearHistory() {
        history.removeAll()
        defaults.removeObject(forKey: StorageKey.history)
    }

    private func historyUpsert(_ verse: Verse) {
        if let existingIndex = history.firstIndex(of: verse) {
            history.remove(at: existingIndex)
        }
        history.insert(verse, at: 0)
        try? defaults.encode(history, forKey: StorageKey.history)
    }

    private func clampCurrentIndex() {
        guard !verseDeck.isEmpty else {
            currentVerseIndex = 0
            return
        }
        currentVerseIndex = currentVerseIndex.clamped(to: 0..<(verseDeck.count))
    }
}

extension AppState {
    enum StorageKey {
        static let onboardingCompleted = "walkworthy.onboardingCompleted"
        static let useProfilePersonalization = "walkworthy.settings.useProfilePersonalization"
        static let useFakeCanvas = "walkworthy.settings.useFakeCanvas"
        static let canvasLinked = "walkworthy.canvas.linked"
        static let translation = "walkworthy.settings.translation"
        static let currentVerseIndex = "walkworthy.home.currentVerseIndex"
        static let history = "walkworthy.history.verses"
        static let canvasSummary = "walkworthy.canvas.summary"
        static let profileAge = "walkworthy.profile.age"
        static let profileMajor = "walkworthy.profile.major"
        static let profileGender = "walkworthy.profile.gender"
        static let profileHobbies = "walkworthy.profile.hobbies"
        static let profileOptIn = "walkworthy.profile.optIn"
    }
}

private extension UserDefaults {
    func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        set(data, forKey: key)
    }

    func decode<T: Decodable>(_ type: T.Type = T.self, forKey key: String) throws -> T {
        guard let data = data(forKey: key) else {
            throw DecodingError.valueNotFound(type, .init(codingPath: [], debugDescription: "No data for key \(key)"))
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        guard !range.isEmpty else { return 0 }
        if self < range.lowerBound { return range.lowerBound }
        if self >= range.upperBound { return range.upperBound - 1 }
        return self
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}