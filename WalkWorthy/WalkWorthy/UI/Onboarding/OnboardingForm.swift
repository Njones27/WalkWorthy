//
//  OnboardingForm.swift
//  WalkWorthy
//
//  Collects lightweight profile preferences and stores them locally.
//

import SwiftUI

struct OnboardingForm: View {
    @EnvironmentObject private var appState: AppState
    @State private var ageText: String = ""
    @State private var major: String = ""
    @State private var gender: Gender = .male
    @State private var selectedHobbies: Set<String> = []
    @State private var optIn: Bool = true
    @FocusState private var focusedField: Field?

    enum Field {
        case age
        case major
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Let's personalize")
            .toolbarTitleDisplayMode(.inline)
        }
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

    private var hobbiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hobbies")
                .font(.headline)
            Text("Select all that spark joy right now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(Hobby.allCases, id: \.rawValue) { hobby in
                    TagChip(label: hobby.label, isSelected: selectedHobbies.contains(hobby.label)) {
                        toggleHobby(hobby.label)
                    }
                }
            }
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
        Button(action: saveProfile) {
            Label("Save and continue", systemImage: "arrow.forward.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .accessibilityHint("Saves your preferences locally and continues to the app.")
    }

    private var gradient: some View {
        LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.6)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private func loadProfile() {
        let profile = appState.loadProfile()
        if let age = profile.age {
            ageText = String(age)
        }
        major = profile.major
        gender = profile.gender
        selectedHobbies = profile.hobbies
        optIn = profile.optIn
    }

    private func toggleHobby(_ label: String) {
        if selectedHobbies.contains(label) {
            selectedHobbies.remove(label)
        } else {
            selectedHobbies.insert(label)
        }
    }

    private func saveProfile() {
        focusedField = nil
        let age = Int(ageText)
        appState.updateProfile(age: age, major: major, gender: gender, hobbies: selectedHobbies, optIn: optIn)
        appState.markOnboardingComplete()
        appState.refreshEncouragementDeck()
    }
}
