# Ollameter Requirements

Status: Draft v3 (2026-10-17)
Owner: leocwlau
Source of truth for scope. Implementation must follow this document; changes to scope require updating this file first.

## 1. Overview

Ollameter is a native macOS menu bar application that shows the user's remaining Ollama cloud credits at a glance. Clicking the menu bar icon opens a detailed view with credit balance, key management, and optionally usage history.

Balance data comes exclusively from the Ollama cloud balance API documented at https://docs.ollama.com/api/balance. Usage history, when included, uses the companion API documented at https://docs.ollama.com/api/cloud-usage.

## 2. Goals

-   Show remaining Ollama cloud credits in the macOS menu bar without opening a browser.
-   Let the user enter and update their Ollama API key from inside the app.
-   Poll the balance API at a conservative rate that respects the documented limits.
-   Keep the app lightweight: no Electron, no web wrapper, native Swift.
-   Keep the codebase migratable to a standard Xcode project with minimal rework.

## 3. Non-goals

-   Showing local Ollama runtime state (loaded models, VRAM) as the balance metric.
-   Chatting with or proxying requests to Ollama models.
-   Supporting multiple cloud accounts simultaneously (may be revisited later).

## 4. Platform and architecture

-   Platform: macOS 13.0+.
-   Language: Swift.
-   UI framework: AppKit for the menu bar item; SwiftUI or AppKit for detail and key-entry views (in code, no Interface Builder).
-   Build system today: SwiftPM executable target plus `scripts/build-app.sh`, which packages and ad-hoc signs `Ollameter.app`.
-   Migration path: when needed, move to an Xcode project generated with `xcodegen`. Swift sources and shared logic carry over largely unchanged. The build script is removed or reduced to a thin wrapper around `xcodebuild` at that point.

AppKit-only code (menu bar item, popover hosting) must not be mixed into files the iOS target would need to compile.

### Distribution and signing

-   Current: `scripts/build-app.sh` produces an ad-hoc signed `Ollameter.app` for local use; no Apple Developer Program membership is required. Rebuilds rotate a fresh ad-hoc identity, which can occasionally re-prompt for keychain authorization.
-   Upgrade path 1, notarized direct distribution (~0.5-1 day first-time setup): Apple Developer Program membership ($99/year), a Developer ID Application certificate, hardened runtime signing (`--options runtime`), a minimal entitlements file, and a `notarytool` submit + `stapler` step added to the scripts. No app-logic changes expected; this also stabilizes keychain item ACLs across rebuilds. Notary turnaround after the first run is typically minutes.
-   Upgrade path 2, App Store (1-3 days of setup plus review turnaround per release): everything in path 1 plus App Sandbox entitlements (`com.apple.security.app-sandbox`, `com.apple.security.network.client`, `keychain-access-groups`), an App Store Connect app record with metadata and screenshots, upload via Transporter or `xcodebuild -exportArchive`, and sandboxes-keychain verification. Sparkle-style in-app updaters are not usable in Mac App Store builds; review rounds add day-scale latency to every release.

## 5. Data source: Ollama cloud balance API

### 5.1 Endpoints

Primary (balance):

```
GET https://ollama.com/api/balance
Authorization: Bearer <API key>
```

This endpoint takes no query parameters. It is the only source for the menu bar metric in v1.

Optional secondary (usage history, per https://docs.ollama.com/api/cloud-usage):

```
GET https://ollama.com/api/usage?range=24h|7d|30d
Authorization: Bearer <API key>
```

Query parameters: `range` (`24h`, `7d`, `30d`), `scope` (`self` or `team`), and `group_by=model` for per-model breakdowns. This endpoint is used for the usage history display.

### 5.2 Response shape

The balance response contains:

-   `included`: for current credit-based plans, `balance_usd` (remaining), `allowance_usd` (full-period credits), and `period` with UTC `from` (inclusive) and `until` (exclusive) timestamps following the plan's monthly reset schedule.
-   Legacy plans return `session` and `weekly` objects inside `included` instead, each with `remaining_percent` (0-100) and `resets_at`. The app must handle both shapes; which fields appear is plan-dependent, not user-configurable.
-   `purchased`: `balance_usd` for unexpired purchased credits.

When usage history is implemented, the usage response contains `range`, `scope`, `granularity`, `from`, `until`, and `group_by`; `totals`; and chronological `buckets`. A 24h response normally has 25 hourly buckets, while 7d and 30d responses have 8 and 31 daily buckets. The active final bucket is marked `partial`. Each bucket and the aggregate object can contain the metric fields `request_count`, `usage_usd`, `input_tokens`, `cached_input_tokens`, and `output_tokens`; when `group_by=model`, each totals object and bucket can contain `groups`. Each group uses `model` for its name and can include the same metric fields. Credit-plan usage groups can include `usage_usd`, while groups representing legacy-plan activity report request counts only. Up to 10 groups are returned per response, ranked by `usage_usd` for credit plans and `request_count` for legacy activity; additional usage is combined in a remainder bucket rather than emitted as another group.

The API reference itself documents no session window length. The app uses the 5-hour session cycle documented at https://ollama.com/pricing (session limits reset every 5 hours, weekly every 7 days; community probes corroborate globally synchronized resets) for pace computations, degrading to a neutral session fill if the 5-hour assumption fails at runtime.

Note: exact field names must be verified against https://docs.ollama.com/api/balance and https://docs.ollama.com/api/cloud-usage at implementation time; this section records intent, not a verbatim schema.

### 5.3 Rate limits

The balance API is limited to 10 requests per minute per user, shared across API keys and devices. The app therefore:

-   Polls automatically once per 60 seconds, with no manual refresh.
-   Issues 4 requests per cycle, inside the 10/minute limit: `/api/balance` once, and `/api/usage` three times with ranges `24h`, `7d`, and `30d`.
-   Applies exponential backoff when it receives a rate-limit response.

## 6. Functional requirements

### Menu bar display

-   FR-1: The app runs as a menu bar (status bar) item with no document window and no Dock icon (`LSUIElement = true`).
-   FR-2: The menu bar title is plan-dependent. For new (credit-based) plans it shows the usage pace delta in percentage points: percentage of credits used minus percentage of the billing period elapsed, rendered with an explicit sign (for example `+20%`, `-3%`, `0%`). Positive values render red; negative and zero values render green. The bar always shows this delta alone; remaining USD and other balance detail live in the popover. The delta is bounded to at most +100 percentage points (credit usage cannot exceed the allowance within a period), so no special handling is needed in the first minutes of a billing period; if included usage ever exceeds the allowance, the displayed delta is capped at +100 percentage points. For legacy plans the bar shows a compact single-line summary combining session and weekly state: `S <session remaining>% <h:mm till reset> W <weekly remaining>% <d:h till reset>` (for example `S 64% 2:10 W 81% 5d:4h`).
-   FR-3: The title updates on each successful poll.
-   FR-4: When data cannot be fetched, the menu bar shows a distinguishable offline/error state, not stale data presented as current (see section 8).

### Usage detail UI

-   FR-5: Clicking the status item opens a popover window anchored under the icon, hosting a small SwiftUI dashboard. Content and behavior follow FR-6 to FR-15.
-   FR-6 (credit-based plans): The popover shows: the balance fields (`balance_usd`, `allowance_usd`, the period reset time `period.until`, and `purchased.balance_usd`); a usage bar, a blue track representing the full allowance filled from the left with the used amount (`allowance_usd` minus `balance_usd`) over the allowance and rendered green when the usage percentage is less than or equal to the elapsed-time percentage and red when it is higher; a period bar, a blue track representing the full period filled from the left with the percentage of time passed, rendered green; and a model usage list, one row per model showing its name, `request_count`, and `usage_usd`, sourced from the polling cycle's usage responses fetched with `group_by=model` (FR-14). The usage pace delta from FR-2 remains the headline metric above these details.
-   FR-7 (legacy plans): The popover shows: the session and weekly limit bars, blue tracks representing the full session and weekly limits, each filled from the left with the used percentage (100 minus `remaining_percent`); both bars render green when their used percentage is less than or equal to the elapsed-time percentage and red when higher, with elapsed time computed over the fixed windows ending at `resets_at` (7 days for weekly; 5 hours for session), and the session bar falling back to a neutral fill if `resets_at` is more than 5 hours away or the computation is otherwise ill-defined; the reset times as `h:mm` till reset for the session line and `d:h` till reset for the weekly line, matching the compact bar summary in FR-2; and a model usage list, one row per model showing its name and `request_count`, sourced from the polling cycle's usage responses fetched with `group_by=model` (FR-14), with `usage_usd` displayed only when present, because the API reports request counts only for legacy-plan activity and ranks groups by request count.
-   FR-8: The usage endpoint is implemented for the usage history display: totals plus chronological buckets for the selected range, rendered as a list in the popover. All three ranges (24h, 7d, 30d) are fetched on every polling cycle, so FR-9's range switcher changes instantly with no network activity. For accounts whose activity includes legacy-plan requests, dollar and token totals are unavailable; the display falls back to request counts.
-   FR-9: The user can change the usage history's displayed range via the popover's range switcher (24h / 7d / 30d), which is the only control surface for the range; each launch starts at 24h (both points resolved 2026-10-17).

### API key management

-   FR-10: If no API key is stored, the app surfaces key entry on first launch and whenever balance fetch fails due to missing credentials.
-   FR-11: The user can enter and later replace the API key through in-app UI.
-   FR-12: The API key is stored in macOS Keychain, not plaintext preferences.
-   FR-13: The key is sent only to `https://ollama.com` over HTTPS and is never logged, echoed in full, or included in diagnostics.

### Polling and refresh

-   FR-14: The app polls automatically once per 60 seconds. Each cycle calls `/api/balance` once and `/api/usage` three times with ranges `24h`, `7d`, and `30d` (each usage call includes `group_by=model`, so the same responses also serve FR-6's model list).
-   FR-15: There is no manual refresh; the app and popover always reflect the most recent polling cycle.

## 7. Security and privacy

-   NFR-1: The API key is stored only in Keychain. It must never be written to UserDefaults, config files, or logs.
-   NFR-2: All API traffic uses HTTPS to `ollama.com`.
-   NFR-3: The API key is never rendered in full in any UI, log line, or error message.
-   NFR-4: No telemetry or analytics are sent anywhere.

## 8. States and error handling

The app must distinguish these states in both the menu bar and the detail view:

-   S1 No API key: menu bar shows a neutral indicator (for example `Set key`); detail view shows key entry.
-   S2 Valid key, data loading: menu bar shows last known good data or `...`; detail view shows progress.
-   S3 Valid key, data loaded: menu bar shows the primary metric; detail view shows balance and reset time.
-   S4 Invalid key (401/403): menu bar shows an error indicator; detail view surfaces the error and key re-entry.
-   S5 Network offline or request failure: menu bar shows the offline state; detail view shows the error and the age of last good data.
-   S6 Rate limited: menu bar keeps last good data; detail view shows a backoff notice.

Last-known-good data may be shown with an explicit "as of <time>" indicator in the detail view, never presented as live current data.

## 9. Milestones

-   M1 Balance core: balance API client, key storage, key entry path, menu bar metric per FR-2 (both plan shapes), 60s polling, error states S1-S6 basic.
-   M2 Detail UI: popover with credit-based balance fields, allowance/period bars, model usage list, and usage history list with range switcher (FR-6, FR-8, FR-9), or the legacy two-line layout (FR-7), old-data indicator, key replacement UI.
-   M3 Hardening: rate-limit backoff, retries, unit tests for the client, release packaging script updates.

## 10. Testing and verification

-   The balance and usage clients must be unit-testable against canned JSON fixtures for both modern and legacy balance shapes, plus grouped usage responses for FR-6's model list.
-   Manual verification matrix: with valid key, with invalid key, with no key, offline, and rate-limited behavior.
-   Release build must produce a working `Ollameter.app` via `scripts/build-app.sh` (or its Xcode-based successor) that launches as a menu bar app with no Dock icon.

## 11. Open decisions

These block implementation details, not the plan. Each has a recommended default; the owner may override by editing this section. OQ identifiers are permanent: when a decision is resolved, its entry is removed in place without renumbering; new decisions take the next unused ID.
