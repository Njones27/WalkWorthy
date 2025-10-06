//
//  OnboardingForm.swift
//  WalkWorthy
//
//  Collects lightweight profile preferences and stores them locally.
//

import SwiftUI

struct OnboardingForm: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var ageText: String = ""
    @State private var major: String = ""
    @State private var gender: Gender = .male
    @State private var selectedHobbies: Set<String> = []
    @State private var customHobby: String = ""
    @State private var optIn: Bool = true
    @State private var ageError: String?
    @State private var majorError: String?
    @State private var hobbiesError: String?
    @State private var isEditingExistingProfile = false
    @FocusState private var focusedField: Field?

    enum Field {
        case age
        case major
    }

    var body: some View {
        Group {
            if appState.onboardingCompleted {
                formContent
            } else {
                NavigationStack {
                    formContent
                }
            }
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ageSection
                majorSection
                genderSection
                hobbiesSection
                optInSection
                privacyCopy
                primaryButton
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
        }
        .background(gradient)
        .onAppear(perform: loadProfile)
        .onChange(of: ageText) {
            if ageError != nil { ageError = nil }
        }
        .onChange(of: major) {
            if majorError != nil { majorError = nil }
        }
        .onChange(of: selectedHobbies) {
            if hobbiesError != nil { hobbiesError = nil }
        }
        .navigationTitle("Let's personalize")
        .toolbarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to WalkWorthy")
                .font(.largeTitle.bold())
            Text("Help us tailor encouragements to your rhythms. Nothing here leaves your device yet.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Age")
                .font(.headline)
            TextField("18", text: $ageText)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding()
                .glassCard()
                .focused($focusedField, equals: .age)
                .accessibilityLabel("Age")
            if let ageError {
                Text(ageError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var majorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Major")
                .font(.headline)
            TextField("Biblical Studies", text: $major)
                .textContentType(.jobTitle)
                .padding()
                .glassCard()
                .focused($focusedField, equals: .major)
                .accessibilityLabel("Major")
            if let majorError {
                Text(majorError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gender")
                .font(.headline)
            Picker("Gender", selection: $gender) {
                ForEach(Gender.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var hobbiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hobbies")
                .font(.headline)
            Text("Pick a few that spark joy, or add your own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(Hobby.allCases, id: \.rawValue) { hobby in
                    TagChip(label: hobby.label, isSelected: selectedHobbies.contains(hobby.label)) {
                        toggleHobby(hobby.label)
                    }
                }
                ForEach(customHobbyChips, id: \.self) { hobby in
                    TagChip(label: hobby, isSelected: selectedHobbies.contains(hobby)) {
                        toggleHobby(hobby)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Don’t see yours? Add it below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    TextField("Add another hobby", text: $customHobby)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .padding()
                        .glassCard()
                        .onSubmit(addCustomHobby)
                    Button("Add", action: addCustomHobby)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAddCustomHobby)
                }
            }
        }
        if let hobbiesError {
            Text(hobbiesError)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var optInSection: some View {
        Toggle(isOn: $optIn) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Receive encouragement nudges")
                    .font(.headline)
                Text("We’ll keep them gentle and focused on Scripture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(.top, 12)
    }

    private var privacyCopy: some View {
        Text("Your responses are stored securely on this device only during the UI sprint. We’ll prompt before syncing to the cloud later.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private var primaryButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shouldShowIncompleteHint {
                Text("Tell us a little about you to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button(action: saveProfile) {
                Label("Save and continue", systemImage: "arrow.forward.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Saves your preferences locally and continues to the app.")
        }
        .padding(.top, 16)
    }

    private var gradient: some View {
        LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.6)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private func loadProfile() {
        isEditingExistingProfile = appState.onboardingCompleted

        let profile = appState.loadProfile()
        if let age = profile.age {
            ageText = String(age)
        } else {
            ageText = ""
        }
        major = profile.major
        gender = profile.gender
        selectedHobbies = profile.hobbies
        optIn = profile.optIn
        resetValidationMessages()

        if !appState.onboardingCompleted {
            DispatchQueue.main.async {
                if profile.age == nil {
                    focusedField = .age
                } else if profile.major.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    focusedField = .major
                }
            }
        }
    }

    private func toggleHobby(_ label: String) {
        if selectedHobbies.contains(label) {
            selectedHobbies.remove(label)
        } else {
            selectedHobbies.insert(label)
        }
    }

    private func addCustomHobby() {
        let trimmed = customHobby.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !selectedHobbies.contains(trimmed) else {
            customHobby = ""
            return
        }
        selectedHobbies.insert(trimmed)
        customHobby = ""
    }

    private var customHobbyChips: [String] {
        let suggested = Set(Hobby.allCases.map(\.label))
        return selectedHobbies
            .filter { !suggested.contains($0) }
            .sorted()
    }

    private var canAddCustomHobby: Bool {
        let trimmed = customHobby.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !selectedHobbies.contains(trimmed)
    }

    private func saveProfile() {
        guard validateProfile() else { return }

        focusedField = nil
        let age = Int(ageText)
        let trimmedMajor = major.trimmingCharacters(in: .whitespacesAndNewlines)
        major = trimmedMajor
        appState.updateProfile(age: age, major: trimmedMajor, gender: gender, hobbies: selectedHobbies, optIn: optIn)
        appState.markOnboardingComplete()
        appState.refreshEncouragementDeck()

        if isEditingExistingProfile {
            dismiss()
        }
    }

    private func validateProfile() -> Bool {
        resetValidationMessages()

        guard let age = Int(ageText), age > 0 else {
            ageError = "Please enter your age."
            focusedField = .age
            return false
        }

        let trimmedMajor = major.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMajor.isEmpty else {
            majorError = "Please share your major."
            focusedField = .major
            return false
        }

        guard !selectedHobbies.isEmpty else {
            hobbiesError = "Pick at least one hobby."
            return false
        }

        return true
    }

    private func resetValidationMessages() {
        ageError = nil
        majorError = nil
        hobbiesError = nil
    }

    private var shouldShowIncompleteHint: Bool {
        !appState.onboardingCompleted && !formIsComplete
    }

    private var formIsComplete: Bool {
        guard let age = Int(ageText), age > 0 else { return false }
        let trimmedMajor = major.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMajor.isEmpty else { return false }
        return !selectedHobbies.isEmpty
    }
}
