# Ollameter

Ollameter is a native macOS menu bar app for Ollama cloud usage. It keeps the live usage pace visible in the menu bar and provides a popover showing balance, allowance, reset, and per-model usage details.

The app supports both current credit-based plans and legacy session/weekly plans. It is intentionally lightweight: there is no Dock icon, document window, Electron wrapper, or telemetry.

## Features

-   Native macOS menu bar item with no Dock icon.
-   Popover dashboard with usage, period, balance, allowance, purchased credits, reset time, and model usage.
-   Automatic model usage range switching between `24h`, `7d`, and `30d`.
-   Support for current credit-based plans and legacy session/weekly plans.
-   API key entry from the popover, stored in macOS Keychain.
-   Automatic polling every 60 seconds.
-   Start-at-login control in the popover.
-   Network-path awareness and reconnect handling.

There is no manual refresh control. The menu bar and popover update after the next successful polling cycle. This is intentional because the public balance API is rate-limited.

## System requirements

-   macOS 13.0 or later.
-   An Ollama cloud account.
-   An Ollama API key with access to the cloud usage endpoints.
-   Network access to `ollama.com`.

## Build prerequisites

Building this project on macOS 13 or later requires a **full Xcode** installation that includes SwiftUI macro plugins. Apple Command Line Tools alone are not sufficient.

A clean clone needs a **full Xcode installation** that includes the SwiftUI macro plugin. Apple Command Line Tools alone are not sufficient for this project.

Install Xcode 15 or later from the Mac App Store, then point macOS at it if needed:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

If your Xcode installation is on another volume or uses a custom name, point the build directly at it:

```sh
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer ./scripts/build-app.sh
```

The script uses Apple-provided tools only: `swift`, `sips`, `iconutil`, and `codesign`. It does not require Homebrew, Python, Node.js, CocoaPods, or any third-party Swift package dependencies.

Command Line Tools alone are not sufficient because SwiftUI macro plugins are only shipped with full Xcode. If `./scripts/build-app.sh` reports a missing SwiftUI macro plugin, set `DEVELOPER_DIR` to a full Xcode installation's `Contents/Developer` directory or switch `xcode-select` to that install.

## Install and start

1. Build the app:

    ```sh
    ./scripts/build-app.sh
    ```

2. Copy the generated bundle to `/Applications`:

    ```sh
    cp -R .build/release/Ollameter.app /Applications/
    ```

3. Launch `/Applications/Ollameter.app`.

4. Enter your Ollama API key when the app prompts for it.

5. Open Ollameter from the menu bar and enable `Start at login` if needed.

Installing in `/Applications` is recommended for a stable login item. Applications on removable, network-mounted, or re-created build paths may not be available when macOS starts the login item.

## Build, test, and development

The app uses SwiftPM rather than an Xcode project. Package sources and app logic remain migratable to a standard Xcode project later.

Build and test directly:

```sh
swift build
swift test
```

Package an ad-hoc signed app bundle:

```sh
./scripts/build-app.sh
```

The packaged app is written to `.build/release/Ollameter.app`.

To open the SwiftPM package in Xcode:

```sh
open Package.swift
```

## Using the popover

Click the Ollameter icon in the menu bar to open the popover. It closes automatically when a click happens outside the popover.

Depending on the account's plan, the popover can show:

-   Used amount, remaining balance, and full allowance.
-   Usage percentage and elapsed-time percentage.
-   Purchased credits, when the account has them.
-   The next reset time.
-   Per-model request counts and dollar usage, when available.
-   Legacy session and weekly limit progress.
-   The `Start at login` toggle.
-   API key replacement.
-   Last update time and quit control.

The model usage switcher supports `24h`, `7d`, and `30d`. Each launch starts at `24h`. Switching ranges is local and instant because all three ranges are fetched during the regular polling cycle.

## Menu bar states

For current credit-based plans, Ollameter shows the usage pace delta: percentage of allowance used minus percentage of the billing period elapsed. Values have one decimal place. Positive values are dark red, meaning usage is ahead of elapsed time. Negative and zero values are green.

For legacy plans, the menu bar shows compact session and weekly states in this pattern:

```text
S 64.0% 2:10 W 81.0% 5d:4h
```

Other menu-bar states include:

| State                 | Meaning                                                                       | Likely action                                      |
| --------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------- |
| `Set key`             | No API key is stored.                                                         | Enter an Ollama API key in the popover.            |
| `...`                 | Initial data loading, or no usable balance shape is available yet.            | Wait for the next cycle.                           |
| `Waiting for network` | No satisfied network path has been reported.                                  | Connect to the internet.                           |
| `Unable to connect`   | A network path exists, but `ollama.com` or the API is unreachable or invalid. | Check connectivity, VPN, and network restrictions. |
| `Auth error`          | The API key was rejected by HTTP 401/403.                                     | Replace or renew the API key.                      |
| `Rate limited`        | Ollama returned HTTP 429.                                                     | Wait; the client applies backoff.                  |

The popover does not render raw usage-history buckets. It uses the API's aggregate per-model groups only.

If recent data exists while the network or API is unavailable, the popover keeps that last-known data visible and shows the last update time. It does not present stale data as a fresh result.

## API and polling

Ollameter uses only the Ollama cloud APIs documented by Ollama:

-   [Balance API](https://docs.ollama.com/api/balance)
-   [Cloud usage API](https://docs.ollama.com/api/cloud-usage)

Each 60-second polling cycle sends four requests:

```text
GET /api/balance
GET /api/usage?range=24h&group_by=model
GET /api/usage?range=7d&group_by=model
GET /api/usage?range=30d&group_by=model
```

The balance endpoint drives the main cloud-plan metric. The usage endpoints drive the model usage list. Ollameter does not query a local Ollama daemon.

## Privacy

-   The API key is stored only in the macOS Keychain.
-   Requests and the API key use HTTPS to `ollama.com`.
-   The key is not logged, displayed in full, or exported.
-   No telemetry or analytics are collected.
-   Use details are kept in memory for the latest polling results only.

The Keychain may ask for authorization after a significantly changed or rebuilt ad-hoc signed binary is launched.

## License

See [LICENSE](LICENSE).
