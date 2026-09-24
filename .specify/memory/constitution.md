<!--
SYNC IMPACT REPORT
==================
Version Change: Initial Template (unratified) → 1.0.0
Modified Principles:
  - [PRINCIPLE_1_NAME] → I. Native Rust Authority & Narrow ABI
  - [PRINCIPLE_2_NAME] → II. Actor Isolation & Off-Main-Actor Execution
  - [PRINCIPLE_3_NAME] → III. Tiered & Independent Testing
  - [PRINCIPLE_4_NAME] → IV. Focused, Imperative Commits & Clean PR Hygiene
  - [PRINCIPLE_5_NAME] → V. Strict Script Automation & AGPL-3.0 Compliance
Added Sections:
  - Technology Stack & Technical Constraints
  - Development Workflow & Quality Gates
Removed Sections:
  - None
Follow-up TODOs:
  - None (all template placeholders resolved with repository-specific standards)
-->

# Manki Constitution

## Core Principles

### I. Native Rust Authority & Narrow ABI
Rust (`rslib`) MUST remain the sole source of truth for collection database storage, scheduling algorithms, card and note rendering templates, media handling, and AnkiWeb sync behavior. Swift code MUST NOT reimplement Anki scheduling, collection schemas, or network sync logic. The native C ABI (`AnkiRustBridge`) MUST remain narrow, application-independent, and versioned (`MANKI_ANKI_ABI_VERSION`). New application features MUST dispatch requests through the generic protobuf RPC runner (`manki_anki_backend_run`) rather than exporting specialized C functions.

### II. Actor Isolation & Off-Main-Actor Execution
All UI-bound application state and SwiftUI view models MUST be bound to `@MainActor`. All blocking native bridge operations, protobuf serialization and deserialization, file I/O, and heavy computations MUST execute off the main actor (e.g., in background cooperative tasks). Swift wrappers MUST ensure thread safety by serializing access to rslib handles, strictly preventing handles from closing while requests are in progress.

### III. Tiered & Independent Testing
Automated tests MUST be strictly segregated by platform dependencies:
- Platform-independent business logic, badge calculations, and models in `Tests/DueBadgeCoreTests/` MUST run via `./scripts/test-linux.sh` and remain completely free of dependencies on UIKit, Xcode, networks, or generated XCFrameworks.
- App integration and view model behaviors belong in `MankiTests`.
- Visual regressions and stable screenshot flows belong in `MankiUITests` using deterministic test fixtures.
Platform-independent tests MUST pass locally before any code submission.

### IV. Focused, Imperative Commits & Clean PR Hygiene
All commit messages MUST use short, imperative subjects (e.g., `Build deck list navigation and sync actions`). Changes MUST be kept focused and atomic. Pull requests MUST document intended behavior, outline validation steps, reference tracking issues, and explicitly highlight changes to native bridges or dependencies. Screenshots MUST be provided for visible UI updates. Repository secrets, signing certificates, `Vendor/`, generated build outputs, and compiled XCFrameworks MUST NEVER be committed.

### V. Strict Script Automation & AGPL-3.0 Compliance
All shell automation scripts under `scripts/` MUST enable strict mode (`set -euo pipefail`), resolve filesystem paths relative to the repository root, and quote variables. Because Anki `rslib` is licensed under AGPL-3.0-or-later, all distributed binaries and framework artifacts MUST comply with AGPL corresponding-source disclosure obligations. Third-party pinned sources MUST remain managed via automated bootstrap scripts rather than ad-hoc vendoring.

## Technology Stack & Technical Constraints

- **Language & Runtime**: Swift 5.9+ with SwiftUI (iOS 17 SDK target) and Rust with Apple-silicon simulator (`aarch64-apple-ios-sim`) and device (`aarch64-apple-ios`) targets.
- **Build Tooling**: Xcode 15+, Cargo, and Protocol Buffers compiler (`protoc`).
- **Code Style & Formatting**: Four-space indentation in Swift and Rust, concise declaration-focused structure, `UpperCamelCase` for types, `lowerCamelCase` for functions and properties, and `testExpectedBehavior` for test methods.
- **Binary & Framework Packaging**: Native framework slice generation via `scripts/build-anki-xcframework.sh` writing to `Frameworks/MankiAnkiRust.xcframework` (or cached CI artifacts). Application bundle identifier is `com.rxdx.manki`.

## Development Workflow & Quality Gates

- **Local Pre-Submission Gate**: Run `./scripts/test-linux.sh` before submitting changes to ensure platform-independent Swift tests pass.
- **Native Bridge Gate**: Any changes touching `AnkiRustBridge/`, pinned `rslib` versions, or C headers require validation through `./scripts/build-anki-xcframework.sh` and Xcode build verification.
- **CI & Release Pipeline**: GitHub Actions workflows run portable tests on Ubuntu in parallel and trigger macOS workers for simulator validation, unsigned release IPA generation (`Manki-unsigned.ipa`), and UI screenshot captures.
- **Security & Secret Protection**: No signing certificates, keys, or credentials may be stored in repository files; signing profiles and certificates remain external or injected via protected CI secrets.

## Governance

This constitution defines the non-negotiable architectural boundaries and engineering rules of Manki. It supersedes informal conventions and general assistant defaults.

- **Amendment Procedure**: Amendments require an updated sync impact report, explicit rationale, and consensus via pull request review.
- **Versioning Policy**: Semantic versioning MUST be applied:
  - MAJOR: Incompatible governance changes, removal or fundamental restructuring of core architectural boundaries.
  - MINOR: Addition of new principles, new quality gates, or materially expanded governance sections.
  - PATCH: Clarifications, wording corrections, typo fixes, or non-semantic refinements.
- **Compliance Review**: All proposed pull requests and automated coding workflows MUST verify adherence to these principles during review and implementation.

**Version**: 1.0.0 | **Ratified**: 2026-09-16 | **Last Amended**: 2026-09-24
