//
//  AppState.swift
//  WalkWorthy
//
//  Created for UI-only sprint.
//

import Foundation
import SwiftUI
import Combine
import AuthenticationServices

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
    @Published var isAuthenticated: Bool {
        didSet {
            if !isAuthenticated {
                latestScanSummary = nil
                encouragementStatusMessage = nil
                latestScanError = nil
                hasFreshEncouragement = true
            }
        }
    }
    @Published var isScanning: Bool
    @Published var latestScanSummary: ScanLogSummary?
    @Published var latestScanError: String?
    @Published var encouragementStatusMessage: String?
    @Published var hasFreshEncouragement: Bool
    @Published var authenticationNotice: String?

    private let apiClient: any EncouragementAPI
    private let notificationScheduler: NotificationScheduler
    private let defaults: UserDefaults
    private let config: Config
    private let authSession: AuthSession?
    private let liveAPIClient: LiveAPIClient?
    private lazy var canvasLinkCoordinator: CanvasLinkCoordinator? = {
        guard let authSession, let liveAPIClient else { return nil }
        return CanvasLinkCoordinator(config: config, authSession: authSession, apiClient: liveAPIClient)
    }()
    private lazy var signInCoordinator: HostedUISignInCoordinator? = {
        guard let authSession else { return nil }
        return HostedUISignInCoordinator(config: config, authSession: authSession)
    }()

    init(
        config: Config = .shared,
        apiClient: any EncouragementAPI = MockAPIClient(),
        authSession: AuthSession? = nil,
        notificationScheduler: NotificationScheduler = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.config = config
        self.apiClient = apiClient
        self.authSession = authSession
        self.liveAPIClient = apiClient as? LiveAPIClient
        self.notificationScheduler = notificationScheduler
        self.defaults = defaults
        self.isAuthenticated = config.apiMode != "live"

        let storedOnboardingCompleted = defaults.bool(forKey: StorageKey.onboardingCompleted)
        if storedOnboardingCompleted && !Self.hasStoredProfile(in: defaults) {
            defaults.set(false, forKey: StorageKey.onboardingCompleted)
            onboardingCompleted = false
        } else {
            onboardingCompleted = storedOnboardingCompleted
        }
        useProfilePersonalization = defaults.object(forKey: StorageKey.useProfilePersonalization) as? Bool ?? true
        useFakeCanvas = defaults.object(forKey: StorageKey.useFakeCanvas) as? Bool ?? config.useFakeCanvas
        isCanvasLinked = defaults.object(forKey: StorageKey.canvasLinked) as? Bool ?? false
        selectedTranslation = Translation(rawValue: defaults.string(forKey: StorageKey.translation) ?? "") ?? config.defaultTranslation
        showPopups = false
        currentVerseIndex = defaults.integer(forKey: StorageKey.currentVerseIndex)
        verseDeck = MockData.verses
        history = (try? defaults.decode([Verse].self, forKey: StorageKey.history)) ?? []
        canvasSummary = try? defaults.decode(TodayCanvas.self, forKey: StorageKey.canvasSummary)
        isScanning = false
        latestScanSummary = nil
        latestScanError = nil
        encouragementStatusMessage = nil
        hasFreshEncouragement = true

        if config.apiMode == "live" && !onboardingCompleted {
            isAuthenticated = false
            Task {
                if let authSession {
                    try? await authSession.signOut()
                }
            }
        }

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
        let trimmedMajor = major.trimmingCharacters(in: .whitespacesAndNewlines)
        if let age {
            defaults.set(age, forKey: StorageKey.profileAge)
        } else {
            defaults.removeObject(forKey: StorageKey.profileAge)
        }
        defaults.set(trimmedMajor, forKey: StorageKey.profileMajor)
        defaults.set(gender.rawValue, forKey: StorageKey.profileGender)
        defaults.set(Array(hobbies), forKey: StorageKey.profileHobbies)
        defaults.set(optIn, forKey: StorageKey.profileOptIn)

        syncProfile(age: age, major: trimmedMajor, gender: gender, hobbies: hobbies, optIn: optIn)
    }

    func loadProfile() -> OnboardingProfile {
        let age = defaults.value(forKey: StorageKey.profileAge) as? Int
        let major = defaults.string(forKey: StorageKey.profileMajor) ?? ""
        let gender = Gender(rawValue: defaults.string(forKey: StorageKey.profileGender) ?? "") ?? .male
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
            markCanvasUnlinked()
        }
    }

    func setTranslation(_ translation: Translation) {
        selectedTranslation = translation
        defaults.set(translation.rawValue, forKey: StorageKey.translation)
        syncStoredProfile()
    }

    func toggleCanvasLink() {
        guard useFakeCanvas else { return }
        isCanvasLinked.toggle()
        defaults.set(isCanvasLinked, forKey: StorageKey.canvasLinked)
    }

    func startCanvasLink(anchor: ASPresentationAnchor?) async throws {
        guard isAuthenticated else {
            throw CanvasLinkCoordinator.CanvasLinkError.backend("Please sign in before linking Canvas.")
        }
        guard let coordinator = canvasLinkCoordinator else {
            throw CanvasLinkCoordinator.CanvasLinkError.misconfigured
        }
        let linked = try await coordinator.startLink(from: anchor)
        if linked {
            markCanvasLinked()
        }
    }

    func markCanvasLinked() {
        isCanvasLinked = true
        defaults.set(true, forKey: StorageKey.canvasLinked)
    }

    func markCanvasUnlinked() {
        isCanvasLinked = false
        defaults.set(false, forKey: StorageKey.canvasLinked)
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

    func evaluateAuthentication() async {
        guard config.apiMode == "live" else {
            isAuthenticated = true
            return
        }
        guard let authSession else {
            isAuthenticated = false
            return
        }

        do {
            _ = try await authSession.validBearerToken()
            isAuthenticated = true
            authenticationNotice = nil
        } catch {
            isAuthenticated = false
            authenticationNotice = "Your session has expired. Please sign in again."
        }
    }

    func startSignIn(anchor: ASPresentationAnchor?) async throws {
        guard let coordinator = signInCoordinator else {
            throw HostedUISignInCoordinator.SignInError.misconfigured
        }
        do {
            try await coordinator.startSignIn(from: anchor)
            isAuthenticated = true
            authenticationNotice = nil
        } catch {
            isAuthenticated = false
            if authenticationNotice == nil {
                authenticationNotice = error.localizedDescription
            }
            throw error
        }
    }

    func signOut() {
        guard config.apiMode == "live" else {
            isAuthenticated = false
            return
        }

        Task {
            if let authSession {
                try? await authSession.signOut()
            }

            await MainActor.run { [self] in
                isAuthenticated = false
                authenticationNotice = "You have been signed out. Please sign in again."
                latestScanSummary = nil
                encouragementStatusMessage = nil
                latestScanError = nil
            }
        }
    }

    var isLiveMode: Bool {
        config.apiMode == "live"
    }

    var requiresAuthenticationGate: Bool {
        isLiveMode && !isAuthenticated
    }

    func refreshEncouragementDeck() {
        guard config.apiMode != "live" || isAuthenticated else { return }
        Task {
            do {
                let response = try await apiClient.fetchNext()
                if response.shouldNotify {
                    notificationScheduler.scheduleEncouragementNotification(response.payload)
                }

                if let payload = response.payload {
                    let verse = Verse(payload: payload)
                    await MainActor.run { [self, verse, response] in
                        if !verseDeck.contains(where: { $0.id == verse.id }) {
                            verseDeck.insert(verse, at: 0)
                        } else if let index = verseDeck.firstIndex(where: { $0.id == verse.id }) {
                            verseDeck[index] = verse
                        }
                        clampCurrentIndex()
                        hasFreshEncouragement = true
                        encouragementStatusMessage = statusMessage(forMetadata: response.metadata) ?? encouragementStatusMessage
                        if let metadata = response.metadata {
                            latestScanSummary = metadata
                        }
                        latestScanError = nil
                    }
                } else {
                    await MainActor.run { [self, response] in
                        if let metadata = response.metadata {
                            latestScanSummary = metadata
                            encouragementStatusMessage = statusMessage(forMetadata: metadata)
                        } else if response.shouldNotify == false {
                            encouragementStatusMessage = "No new encouragement yet. We'll try again soon."
                        }
                        hasFreshEncouragement = response.shouldNotify
                        latestScanError = nil
                    }
                }
            } catch {
                await MainActor.run { [self] in
                    latestScanError = error.localizedDescription
                }
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

    func triggerScanNow() {
        if config.apiMode != "live" {
            refreshEncouragementDeck()
            return
        }
        guard isAuthenticated else {
            latestScanError = "Please sign in before running a scan."
            return
        }

        isScanning = true
        latestScanError = nil

        Task {
            do {
                let response = try await apiClient.triggerScanNow()
                await MainActor.run { [self, response] in
                    isScanning = false
                    latestScanSummary = response.log ?? latestScanSummary
                    encouragementStatusMessage = message(for: response)
                    latestScanError = nil
                }
                refreshEncouragementDeck()
            } catch let apiError as APIError {
                await MainActor.run { [self] in
                    isScanning = false
                    switch apiError {
                    case .conflict(let message):
                        latestScanError = message ?? "Link your Canvas account to enable scans."
                    case .unauthorized, .notAuthenticated:
                        latestScanError = nil
                        isAuthenticated = false
                        authenticationNotice = "Your session has expired. Please sign in again."
                    default:
                        latestScanError = apiError.errorDescription ?? "Scan failed."
                    }
                }
            } catch {
                await MainActor.run { [self] in
                    isScanning = false
                    latestScanError = error.localizedDescription
                }
            }
        }
    }

    func clearHistory() {
        history.removeAll()
        defaults.removeObject(forKey: StorageKey.history)
    }

    private func syncProfile(age: Int?, major: String, gender: Gender, hobbies: Set<String>, optIn: Bool) {
        guard config.apiMode == "live", isAuthenticated else { return }
        let profile = OnboardingProfile(age: age, major: major, gender: gender, hobbies: hobbies, optIn: optIn)
        Task {
            await sendProfileUpdate(profile)
        }
    }

    private func syncStoredProfile() {
        guard config.apiMode == "live", isAuthenticated else { return }
        let profile = loadProfile()
        Task {
            await sendProfileUpdate(profile)
        }
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

    private func sendProfileUpdate(_ profile: OnboardingProfile) async {
        guard config.apiMode == "live", isAuthenticated else { return }
        let trimmedMajor = profile.major.trimmingCharacters(in: .whitespacesAndNewlines)
        let hobbies = profile.hobbies.sorted()
        let payload = RemoteUserProfileRequest(
            ageRange: ageRangeString(for: profile.age),
            major: trimmedMajor.isEmpty ? nil : trimmedMajor,
            gender: profile.gender.rawValue.lowercased(),
            hobbies: hobbies.isEmpty ? nil : hobbies,
            optInTailored: profile.optIn,
            translationPreference: selectedTranslation.rawValue
        )

        do {
            try await apiClient.updateUserProfile(payload)
        } catch {
            print("[AppState] Failed to sync profile: \(error)")
        }
    }

    private func statusMessage(forMetadata metadata: ScanLogSummary?) -> String? {
        guard let metadata else {
            return "Fresh encouragement delivered."
        }
        switch metadata.status {
        case .success:
            return "Fresh encouragement delivered from today's scan."
        case .fallback:
            if let reason = metadata.errorMessage, !reason.isEmpty {
                return "Fallback encouragement delivered: \(reason)"
            }
            return "Fallback encouragement delivered from your backup verses."
        }
    }

    private func message(for response: ScanNowResponse) -> String {
        switch response.status {
        case .success:
            return "Scan accepted. We'll deliver a new encouragement shortly."
        case .fallback:
            if let reason = response.log?.errorMessage, !reason.isEmpty {
                return "Fallback encouragement queued: \(reason)"
            }
            return "Fallback encouragement queued. We'll keep looking for a fresh verse."
        }
    }

    private func ageRangeString(for age: Int?) -> String? {
        guard let age else { return nil }
        switch age {
        case ..<18: return "under-18"
        case 18...22: return "18-22"
        case 23...30: return "23-30"
        case 31...40: return "31-40"
        case 41...55: return "41-55"
        case 56...65: return "56-65"
        default: return "65+"
        }
    }
}

private extension AppState {
    static func hasStoredProfile(in defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: StorageKey.profileAge) != nil { return true }
        if defaults.object(forKey: StorageKey.profileMajor) != nil { return true }
        if defaults.object(forKey: StorageKey.profileGender) != nil { return true }
        if defaults.object(forKey: StorageKey.profileHobbies) != nil { return true }
        if defaults.object(forKey: StorageKey.profileOptIn) != nil { return true }
        return false
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
