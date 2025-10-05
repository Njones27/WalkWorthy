
# WalkWorthy — **UI‑Only Sprint Spec** (Stage 1)

Build a **SwiftUI** app with the “liquid glass” aesthetic that runs **without any backend**. Use mocked data and local notifications only. This lets us verify UX before enabling AWS.

## Scope
- No AWS calls. No Canvas OAuth. Everything behind feature flags and mocks.
- Implement the complete UI flows and local notification pipeline.

## Visual & Interaction Guidelines
- Material style: `.ultraThinMaterial` backgrounds, cornerRadius **24**, soft shadows, spring animations for transitions.
- Support Light/Dark, Dynamic Type, VoiceOver labels, and haptics (tap/success).
- Keep text contrast readable on materials.

## Screens & Components
1) **OnboardingForm**
   - Fields: age (Number), major (Text), gender (Picker), hobbies (Chips/multi‑select), opt‑in toggle.
   - Save locally (UserDefaults). Show brief privacy copy.
2) **CanvasLinkView** (Mocked)
   - When `USE_FAKE_CANVAS=true`, show a “Link Canvas (Mock)” button → toggles state to “Linked (mock)”. No OAuth yet.
3) **HomeView (VerseCard)**
   - Glass card showing **ref**, **text**, **encouragement**, and a **translation picker** (ESV/KJV/etc.).
   - Buttons: **Next**, **Previous** (cycles a small local list).
   - Button: **Show Pop‑ups** (stacked/sheet cards for Courage/Rest/Wisdom).
4) **EncouragementPopupsView**
   - Sequence of 3–5 cards with tag labels; swipe to advance; haptics on advance.
5) **HistoryView**
   - List of recent mock verses; tap to open details.
6) **SettingsView**
   - Toggles: Use profile for personalization, Use fake Canvas link.
   - Translation preference (Picker).
   - Button: **Send test notification (10s)** to verify local notifications.
   - Show app/build info.

## Local Notifications & BackgroundTasks
- `NotificationScheduler` requests permission and schedules **local** notifications.
- “Test notification” button schedules `UNTimeIntervalNotificationTrigger` for ~10 secs.
- `BackgroundTasks` registers `com.walkworthy.refresh`; task body loads `Mock/encouragement_next.json` and, if `shouldNotify=true`, schedules a local notification.

**Info.plist additions**
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.walkworthy.refresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>processing</string>
</array>
```

## Mock API Layer
Define a protocol so we can later swap in the real API client.

```swift
protocol EncouragementAPI {
    func fetchNext() async throws -> NextResponse
    func fetchTodayCanvas() async throws -> TodayCanvas
}

struct NextResponse: Codable {
    let shouldNotify: Bool
    let payload: EncouragementPayload?
}
struct EncouragementPayload: Codable, Hashable {
    let id: String
    let ref: String
    let text: String
    let encouragement: String
    let translation: String?
    let expiresAt: String?
}
struct TodayCanvas: Codable {
    let assignmentsToday: [Assignment]
    let examsToday: [Exam]
}
struct Assignment: Codable { let title: String; let due_at: String; let points: Int? }
struct Exam: Codable { let title: String; let when: String }
```

**Mock implementation**: `MockAPIClient` that loads JSON from the app bundle (`Mock/encouragement_next.json`, `Mock/today_canvas.json`).

## Feature Flags
- `API_MODE = mock` (default)
- `USE_FAKE_CANVAS = true`
- `NOTIFICATION_MODE = local`

Create a simple `Config` struct that reads these from Info.plist or `Config.plist`.

## File Structure (suggested)
```
mobile/Sources/
  App/
    WalkWorthyApp.swift
    AppState.swift
    Config.swift
  UI/
    Components/GlassCard.swift
    Components/VerseCard.swift
    Onboarding/OnboardingForm.swift
    Canvas/CanvasLinkView.swift
    Home/HomeView.swift
    Popups/EncouragementPopupsView.swift
    History/HistoryView.swift
    Settings/SettingsView.swift
  Notifications/
    NotificationScheduler.swift
  Background/
    BackgroundTasks.swift
  Mock/
    MockAPIClient.swift
    encouragement_next.json
    today_canvas.json
```

## Quick Tests
- Launch app → complete onboarding → Settings → **Send test notification** → notification appears.
- Home shows verse using mock JSON; change translation → label updates.
- Canvas Link toggles to “Linked (mock)” when tapped.
- Pop‑ups render with liquid‑glass styling and haptics.
- Background refresh registration present; simulate by re‑launching and tapping a “Refresh” button that calls the mock.

## Acceptance Criteria (Stage 1)
- ✅ Compiles & runs on simulator (iOS 16+).
- ✅ Local notifications work via test button.
- ✅ All screens present with liquid‑glass style and smooth navigation.
- ✅ Mock API layer wired; feature flags default to mock/local.
- ✅ No network/AWS calls; no secrets required.
