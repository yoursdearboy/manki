# Repository Guidelines

## Project Structure & Module Organization

`Manki/` contains the SwiftUI application, view model, native-backend wrapper, badge logic, and asset catalog. `MankiCLI/` provides the macOS command-line client. The narrow Rust-to-C bridge lives in `AnkiRustBridge/`; keep Anki collection, scheduling, and sync behavior in the pinned `rslib` dependency rather than reimplementing it in Swift. Unit tests are split between `Tests/DueBadgeCoreTests/` for the Linux-compatible Swift package and `MankiTests/` for app tests. `MankiUITests/` holds deterministic screenshot tests. Build automation belongs in `scripts/`, while Xcode configuration is under `Manki.xcodeproj/`.

## Build, Test, and Development Commands

- `./scripts/test-linux.sh` runs the fast, platform-independent Swift tests; use this before every submission.
- `./scripts/bootstrap-anki-rslib.sh` checks out the pinned Anki source into the ignored `Vendor/` directory.
- `./scripts/build-anki-xcframework.sh` builds device, simulator, and macOS slices at `Frameworks/MankiAnkiRust.xcframework`; it requires Rust, Xcode, and `protoc`.
- `./scripts/build-macos-cli.sh` builds `.build/manki-anki-cli`, reusing a current framework when possible.
- Open `Manki.xcodeproj` in Xcode 15+ for app development. Comment exactly `/run-ios-tests` on a pull request to trigger the opt-in macOS CI workflow.

## Coding Style & Naming Conventions

Use four-space indentation in Swift and Rust, and preserve the repository's concise, declaration-focused style. Name Swift types in `UpperCamelCase`, functions and properties in `lowerCamelCase`, and tests as `testExpectedBehavior`. Keep UI-bound state on `@MainActor`; move blocking backend work off the main actor. Shell scripts should enable strict mode (`set -euo pipefail`), quote paths, and resolve paths relative to the repository.

## Testing Guidelines

Add XCTest coverage beside the relevant target. Keep package tests independent of UIKit, Xcode, the network, and generated frameworks. App behavior belongs in `MankiTests`; stable visual flows belong in `MankiUITests` using existing fixtures. Run Linux tests locally and request iOS validation for changes affecting UI, the Xcode project, or the native bridge.

## Commit & Pull Request Guidelines

Follow the history's short, imperative subjects, such as `Build deck list navigation and sync actions`. Keep commits focused. Pull requests should explain behavior and validation, link the relevant issue, and call out bridge or dependency changes. Include screenshots for visible UI updates and never commit credentials, signing certificates, `Vendor/`, build output, or generated XCFrameworks.
