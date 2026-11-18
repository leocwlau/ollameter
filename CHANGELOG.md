# Changelog

All notable changes to Ollameter are documented here.

## [Unreleased]

## [1.0.1] - 2026-11-18

### Fixed

-   API key entry now supports both `Command-V` and `Control-V`.
-   Valid balance responses with `balance_usd = 0` and `allowance_usd = 0` are no longer reported as invalid.
-   Zero-allowance accounts now show `--` in the menu bar and a zero-balance dashboard instead of an error banner.

## [1.0.0] - 2026-10-18

### Added

-   Menu-bar usage pace indicator for credit-based and legacy plans.
-   Popover with balances, allowance and period progress, reset time, per-model usage, purchased credits, key replacement, launch-at-login, and quit controls.
-   Automatic 60-second polling with `24h`, `7d`, and `30d` model-usage ranges.
-   Network-path awareness and reconnection polling.
