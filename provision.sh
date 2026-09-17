#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <profile.mobileprovision>"
  exit 1
fi

PROFILE="$1"
REPOSITORY="yoursdearboy/manki"
# This is the Actions artifact label. GitHub downloads its contents as a ZIP.
ARTIFACT_NAME="Manki-unsigned-iphone"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is required to download the build artifact"
  exit 1
fi

echo "==> Downloading latest unsigned IPA"
echo "Repository: $REPOSITORY"
echo "Artifact: $ARTIFACT_NAME"

# With no run ID, `gh run download` selects the latest successful workflow run.
gh run download \
  --repo "$REPOSITORY" \
  --name "$ARTIFACT_NAME" \
  --dir "$TMP/artifact"

IPA=$(find "$TMP/artifact" -type f -name '*.ipa' -print -quit)

if [ -z "$IPA" ]; then
  echo "ERROR: Artifact $ARTIFACT_NAME did not contain an IPA"
  exit 1
fi

echo "Downloaded IPA: $IPA"


echo "==> Finding Apple Development signing identity"

IDENTITY=$(
  security find-identity -v -p codesigning |
    sed -n 's/.*"\(Apple Development:.*\)"/\1/p' |
    head -1
)

if [ -z "$IDENTITY" ]; then
  echo "ERROR: Could not find Apple Development signing identity"
  exit 1
fi

echo "Identity: $IDENTITY"


echo
echo "==> Extracting IPA"
echo "IPA: $IPA"
echo "Temporary directory: $TMP"

unzip "$IPA" -d "$TMP"

APP=$(
  find "$TMP/Payload" \
    -maxdepth 1 \
    -name '*.app' \
    -print \
    -quit
)

if [ -z "$APP" ]; then
  echo "ERROR: Could not find .app inside IPA"
  exit 1
fi

echo "Application: $APP"


echo
echo "==> Bundle identifier"
echo "Info.plist: $APP/Info.plist"

/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleIdentifier' \
  "$APP/Info.plist"


echo
echo "==> Decoding provisioning profile"
echo "Profile: $PROFILE"
echo "Decoded profile: $TMP/profile.plist"

security cms -D \
  -i "$PROFILE" \
  -o "$TMP/profile.plist"


echo
echo "==> Provisioning profile application identifier"
echo "Profile: $TMP/profile.plist"

/usr/libexec/PlistBuddy \
  -c 'Print :Entitlements:application-identifier' \
  "$TMP/profile.plist"


echo
echo "==> Embedding provisioning profile"
echo "Source: $PROFILE"
echo "Destination: $APP/embedded.mobileprovision"

cp "$PROFILE" \
  "$APP/embedded.mobileprovision"


echo
echo "==> Extracting signing entitlements"
echo "Destination: $TMP/entitlements.plist"

/usr/libexec/PlistBuddy \
  -x \
  -c 'Print :Entitlements' \
  "$TMP/profile.plist" \
  >"$TMP/entitlements.plist"


echo
echo "==> Entitlements"
echo "File: $TMP/entitlements.plist"

plutil -p "$TMP/entitlements.plist"


echo
echo "==> Signing application"
echo "Application: $APP"
echo "Identity: $IDENTITY"
echo "Entitlements: $TMP/entitlements.plist"

codesign \
  --force \
  --sign "$IDENTITY" \
  --entitlements "$TMP/entitlements.plist" \
  --timestamp=none \
  "$APP"


echo
echo "==> Verifying signature"
echo "Application: $APP"

codesign \
  --verify \
  --deep \
  --strict \
  --verbose=2 \
  "$APP"


echo
echo "==> Connected devices"

xcrun devicectl list devices


YOUR_DEVICE_ID=$(
  xcrun devicectl list devices |
    sed -n 's/.* \([0-9A-Fa-f]\{8\}-[0-9A-Fa-f-]\{27,\}\) .*/\1/p' |
    head -1
)

if [ -z "$YOUR_DEVICE_ID" ]; then
  echo
  echo "ERROR: Could not determine device ID"
  exit 1
fi


echo
echo "==> Selected device"
echo "Device ID: $YOUR_DEVICE_ID"


echo
echo "==> Installing application"
echo "Application: $APP"
echo "Device: $YOUR_DEVICE_ID"

xcrun devicectl device install app \
  --device "$YOUR_DEVICE_ID" \
  "$APP"
