# WalkWorthy

WalkWorthy pairs daily Canvas stressors with timely Scripture encouragements.  
The iOS app now supports both **mock** and **live** modes backed by the Stage 4 AWS stack.

## App Features
- SwiftUI experience with liquid-glass styling across home, history, and settings.
- Cognito Hosted UI sign-in when running in live mode.
- Canvas OAuth linking via `ASWebAuthenticationSession`.
- Manual “Scan Now” trigger with live status metrics (success vs fallback, counts, tags).
- Local history of recently viewed verses with latest scan summary.
- Local notifications when new encouragements arrive.

## Environment Modes
The app reads `Config.plist` alongside `Info.plist`. Override keys to toggle behaviour:

| Key | Description |
| --- | --- |
| `API_MODE` | `mock` (default) keeps locally bundled responses. Set to `live` to use the deployed API. |
| `API_BASE_URL` | HTTPS base for the API Gateway (e.g. `https://abc123.execute-api.us-east-1.amazonaws.com`). |
| `COGNITO_DOMAIN` | Cognito Hosted UI domain (include scheme or leave bare host). |
| `COGNITO_CLIENT_ID` | Cognito app client id configured for the Hosted UI. |
| `COGNITO_REDIRECT_URI` | Custom scheme redirect, defaults to `walkworthy://auth/callback`. Add this URI to the Cognito app client. |
| `CANVAS_BASE_URL` | Canvas instance base URL (e.g. `https://myschool.instructure.com`). |
| `CANVAS_CLIENT_ID` | Canvas OAuth client id registered for WalkWorthy. |
| `CANVAS_REDIRECT_URI` | Canvas OAuth redirect, defaults to `walkworthy://oauth/canvas`. Register this with Canvas. |
| `USE_FAKE_CANVAS` | `true` to keep the mock toggle available. Set `false` in live builds. |
| `DEFAULT_TRANSLATION` | Default translation code (`ESV`, `NIV`, etc.). |
| `NOTIFICATION_MODE` | Currently informational; local notifications are always used. |

> `Config.plist` entries override `Info.plist` values, so you can ship multiple build variants by swapping that file.

## Live Mode Checklist
1. **Cognito Hosted UI**
   - Create an app client with redirect URI `walkworthy://auth/callback`.
   - Allow the `openid profile email` scopes.
   - Populate `COGNITO_DOMAIN` and `COGNITO_CLIENT_ID` in `Config.plist`.
2. **API Gateway**
   - Deploy Stage 3/4 infrastructure and copy the base URL into `API_BASE_URL`.
3. **Canvas OAuth**
   - Register `walkworthy://oauth/canvas` with your Canvas developer keys.
   - Supply `CANVAS_BASE_URL` and `CANVAS_CLIENT_ID`.
4. **Build**
   - Set `API_MODE` to `live` and flip `USE_FAKE_CANVAS` to `false`.
   - Launch the app; you’ll be prompted to sign in, then you can link Canvas.

## Usage Tips
- Tap **Sign in with WalkWorthy** when the authentication gate appears. The session is cached in the keychain and refreshed automatically.
- Use the **Scan Now** button on the Home tab to run an on-demand scan. Status metrics summarise planner items, stressful tasks, and verse candidate counts. Conflicts (Canvas not linked) and auth errors surface inline.
- The **History** tab stores verses locally and shows the latest scan summary for quick diagnostics.
- Settings still include profile personalisation toggles; in live mode profile updates sync to `/user/profile`.

## Mock Mode
Leave `API_MODE` as `mock` for design iteration. Mock JSON lives under `WalkWorthy/Mock/`.
The Canvas tile falls back to the original toggle with sample summary data.

## Building & Running
1. Open `WalkWorthy/WalkWorthy.xcodeproj`.
2. Select the `WalkWorthy` target and desired simulator/device.
3. Update `Config.plist` as needed for mock or live runs.
4. Build & run (`⌘R`).

## Stage 4 Highlights
- Live Cognito authentication flow with sign-in gating.
- Canvas OAuth implementation using backend `/auth/canvas/callback`.
- Live networking layer (`LiveAPIClient`) covering `/encouragement/next`, `/scan/now`, `/user/profile`, `/auth/canvas/callback`.
- UI polish: scan status cards, manual scan action, fallback messaging, refined history view.
- Documentation for configuring the bundle per environment.
