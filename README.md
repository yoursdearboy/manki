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

`AnkiRustBridge` exposes exactly four operations: create a backend, dispatch a protobuf service request, free the returned response buffer, and close the backend.

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

The bootstrap script checks out Anki revision `e64c6b1aee3e8d668fb8bbe084beada8e070d985`, the revision pinned by Amgi at the time this bridge was introduced. The build script compiles iOS device, Apple-silicon simulator, and macOS slices, then writes `Frameworks/MankiAnkiRust.xcframework`, which is already linked by `Manki.xcodeproj`.

Open `Manki.xcodeproj` after the framework has been built. The initial screen starts an rslib backend and confirms that the native engine can initialize.

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

## Fetch decks on macOS

Build the same XCFramework plus a small Swift command-line wrapper:

```sh
./scripts/build-macos-cli.sh
.build/manki-anki-cli --username you@example.com
```

The CLI prompts for the password with terminal echo disabled. It uses the macOS
slice of `MankiAnkiRust.xcframework`; it does not contain its own Anki or sync
implementation. By default it syncs into
`~/Library/Application Support/Manki/collection.anki2` and prints each deck as
`ID<TAB>name`. Use `--collection PATH` to choose another Manki-owned local
collection and `--endpoint URL` for a compatible self-hosted server.

The command intentionally skips media sync: deck names live in the collection,
and avoiding media transfer keeps this read-focused command independent of
media-server and proxy behavior.

It refuses a full upload and an unresolved full-sync conflict. A normal sync
uses Anki’s standard bidirectional semantics, so pass a new `--collection`
path if you need an initial download without existing local changes.

## API contract

The C header is at `AnkiRustBridge/include/manki_anki_rust.h`. Successful calls return raw response protobuf bytes. A status of `1` returns an encoded Anki `BackendError` protobuf, also owned by the caller until `manki_anki_free_response()` is called.

The Swift wrapper serializes calls with a lock: an rslib backend handle must not be closed while a request is in progress. It does not interpret or modify the request and response payloads.

## License

Anki `rslib` is licensed under AGPL-3.0-or-later. Incorporating and distributing the generated framework makes this project subject to that license’s corresponding-source obligations. Review the Anki license before shipping a build.
