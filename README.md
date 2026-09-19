# Manki — native Anki `rslib` experiment

Manki now uses Anki’s Rust backend (`rslib`) through a small C ABI, instead of hand-writing the AnkiWeb sync protocol in Swift. Rust remains the authority for the collection database, scheduling, templates, media, and sync behavior; Swift only owns the interface and forwards protobuf RPC bytes.

The bridge structure is adapted from [Amgi](https://github.com/antigluten/amgi) as a reference implementation. Manki does not depend on Amgi and does not embed its application code.

## Layout

```
SwiftUI
  → MankiAnkiRust XCFramework
  → C ABI (four functions)
  → Anki rslib
```

`AnkiRustBridge` exposes a versioned, application-independent ABI with four
core operations: create a backend, dispatch a protobuf service request, free
the returned response buffer, and close the backend. Its opaque handle and
byte-slice types are usable directly from Swift through the XCFramework's
Clang module. Existing feature-specific entry points remain available as
compatibility helpers, but new application features should use the generic
dispatcher instead of adding framework symbols.

This is intentionally low level. Adding a feature means generating the matching Anki protobuf types and invoking the documented backend service; it does not mean reproducing sync endpoints or collection mutations in Swift.

## Build the iOS framework

Requirements:

- Xcode 15+ and iOS 17 SDK
- Rust and the iOS Rust targets (the build script installs the targets)
- `protoc` available on `PATH` (for example, `brew install protobuf`)

From the repository root:

```sh
./scripts/bootstrap-anki-rslib.sh
./scripts/build-anki-xcframework.sh
```

The bootstrap script checks out Anki revision `e64c6b1aee3e8d668fb8bbe084beada8e070d985`, the revision pinned by Amgi at the time this bridge was introduced. The build script compiles iPhone-device and Apple-silicon simulator slices, then writes `Frameworks/MankiAnkiRust.xcframework`, which is already linked by `Manki.xcodeproj`. Pass `simulator` to build the simulator slice first, or `device` after it to produce the complete two-slice framework.

Open `Manki.xcodeproj` after the framework has been built. The initial screen starts an rslib backend and confirms that the native engine can initialize.

## Run tests

The test suite is split by platform. Agents on a Linux host run the fast,
platform-independent tests with:

```sh
./scripts/test-linux.sh
```

The UI screenshot tests and unsigned iPhone build run on a GitHub-hosted macOS
worker when the manually dispatched **iOS UI screenshots** workflow is run. The
workflow runs portable Swift tests on Ubuntu in parallel, validates the
Apple-silicon simulator before building the release IPA, and publishes the
screenshots, test results, XCFramework, and IPA as artifacts. Enable its
optional landscape input when landscape screenshot variants are required.

### Download the framework from CI

Successful **iOS UI screenshots** workflow runs publish a
`MankiAnkiRust-xcframework-<source hash>` artifact. To avoid compiling Anki
locally, download and extract that artifact so the resulting directory is at
`Frameworks/MankiAnkiRust.xcframework`, then open `Manki.xcodeproj` and build as
usual. The workflow also caches this exact framework based on the bridge
sources, lockfile, and framework build scripts, so unchanged CI runs skip the
expensive Rust compilation.

### Download an unsigned iPhone IPA

The workflow also publishes `Manki-unsigned-iphone`, containing a Release build
named `Manki-unsigned.ipa`. Unlike the screenshot workflow's Simulator build,
this IPA contains an `iphoneos` arm64 application and can be signed later
without recompiling either Swift or Rust.

The IPA is deliberately unsigned and cannot be installed as downloaded. Before
installation, it must be re-signed with an Apple Development or Ad Hoc
certificate and a provisioning profile whose application identifier matches
`com.rxdx.manki`. A development profile must include the target iPhone's UDID.
Tools that support IPA re-signing can consume the artifact directly; a manual
signing flow must embed the profile, apply its entitlements with `codesign`, and
zip the `Payload` directory back into an IPA. The signing certificate's private
key is still required, but no local app compilation is required.

CI could additionally publish a ready-to-install signed IPA only after the
corresponding certificate and provisioning profile are configured as protected
repository secrets. They are intentionally not stored in this repository.

## API contract

The C header is at `AnkiRustBridge/include/manki_anki_rust.h`. Check
`manki_anki_abi_version()` against `MANKI_ANKI_ABI_VERSION`, create one or more
opaque `MankiAnkiBackend` instances, and call `manki_anki_backend_run()` with
the service and method identifiers from Anki's generated backend interface.
Successful calls return raw response protobuf bytes. A status of
`MANKI_ANKI_STATUS_BACKEND_ERROR` returns an encoded Anki `BackendError`
protobuf. In either case, release the owned response exactly once with
`manki_anki_bytes_free()`.

Because the request and response contract is generic, adding a screen or
composing existing collection, scheduler, rendering, and sync RPCs in Swift
does not require a new Rust export or an XCFramework rebuild. Rebuild the
artifact only when updating rslib or the bridge ABI itself. The legacy
`manki_anki_open_backend()`/`manki_anki_run_method()` pair and the original
feature helpers remain exported so existing app binaries continue to work with
the reusable framework.

The Swift wrapper serializes calls with a lock: an rslib backend handle must not be closed while a request is in progress. It does not interpret or modify the request and response payloads.

## License

Anki `rslib` is licensed under AGPL-3.0-or-later. Incorporating and distributing the generated framework makes this project subject to that license’s corresponding-source obligations. Review the Anki license before shipping a build.
