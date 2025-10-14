# WalkWorthy

WalkWorthy pairs daily Canvas stressors with timely Scripture encouragements. The repository delivers both the iOS experience and the AWS CDK infrastructure the prompts describe.

## Guided Build Context
- The `prompts/` directory captures the staged build narrative: it defines the north-star architecture (Canvas + AgentKit + notifications), outlines iterative delivery goals, and sets expectations for code quality and guardrails.
- Every major subsystem—mobile, infrastructure, AgentKit bridge, notifications, Canvas integration—maps back to its prompt to keep requirements discoverable alongside the source.

## Architecture Flow
- **iOS app** (SwiftUI) gathers profile inputs, authenticates with Amazon Cognito, links Canvas via OAuth, and requests encouragements on demand or through background reminders.
- **API Gateway HTTP API** fronts Lambda handlers that coordinate Canvas tokens, run daily scans, and surface encouragement content to the app.
- **Canvas integration** stores refresh tokens in Secrets Manager and scans upcoming assignments/events using `scan-user`.
- **Bible MCP + AgentKit**: verse candidates flow through a lightweight bridge Lambda (`bible-mcp-bridge`) so `scan-user` and the weekday scheduler can invoke AgentKit models with contextual prompts.
- **DynamoDB single-table** design tracks user profiles, Canvas linkage, scan history, and pending encouragement payloads that the app fetches via `/encouragement/next`.
- **EventBridge Scheduler → Lambda** drives the weekday 9am scan (`weekday-scan`) which reuses the same path as on-demand scans, persists new encouragements, and queues notification work.
- **Notification lane** lets the backend mark encouragements ready and allows the app to POST device tokens so future push or local-notification plumbing can fan out.

The net effect is a pipeline where data flows from Canvas → DynamoDB → AgentKit → app, with Cognito-protected endpoints enforcing trust boundaries.

## Current Implementation Highlights
- **Mobile app (SwiftUI)**: onboarding, home scan dashboard, history, and settings views styled with the “liquid glass” treatment. Supports Cognito Hosted UI sign-in, Canvas OAuth linking, manual scans, local verse history, and notification prompts. Mock data remains available for design iteration.
- **Networking layer**: typed async clients hit `/scan/now`, `/encouragement/next`, `/user/profile`, `/auth/canvas/callback`, `/device/register`, and `/encouragement/notify`, automatically attaching Cognito tokens when available.
- **Infrastructure (AWS CDK TypeScript)**: deploys the HTTP API, Lambda handlers (`canvas-callback`, `scan-user`, `weekday-scan`, `encouragement-next`, `notify-user`, `register-device`, `user-profile`, `bible-mcp-bridge`), DynamoDB table binding, Secrets Manager references, EventBridge Scheduler with DLQ, and IAM policies for Canvas token management plus AgentKit access.
- **Data & workflow**: scans compute stress heuristics, fetch verse candidates via the Bible MCP bridge, ask AgentKit to craft the final encouragement, write the result to DynamoDB, and surface it to the client until acknowledged.

## Repository Tour
- `WalkWorthy/`: Xcode project and SwiftUI sources for the iOS client (e.g. `UI/Onboarding/TitleScreenView.swift`, auth/session management, mock payloads).
- `infrastructure/`: AWS CDK app (`infrastructure-stack.ts`) with Lambda handlers under `src/handlers/`.
- `prompts/`: reference prompts that document goals, integration points, security requirements, and CI/CD expectations.

## Working With The App
- Open `WalkWorthy/WalkWorthy.xcodeproj`, select the `WalkWorthy` target, and run on a simulator or device.
- Toggle between mock responses and live API usage by swapping the bundled configuration plist; no source changes are required.
- Sign in through the built-in Cognito Hosted UI, link Canvas via the provided OAuth flow, and use “Scan Now” to exercise the full backend loop.

## Deployment Notes
- Provision the backend by bootstrapping CDK and deploying the stack in `infrastructure/`.
- After deployment, plug the resulting API URL, Cognito settings, and Canvas domain into the app’s configuration bundle to run in live mode.
