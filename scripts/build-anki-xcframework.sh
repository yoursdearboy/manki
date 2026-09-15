#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
root_dir=${script_dir:h}
bridge_dir="$root_dir/AnkiRustBridge"
output_dir="$root_dir/Frameworks/MankiAnkiRust.xcframework"
stamp_file="$root_dir/Frameworks/.manki-anki-rust.stamp"
stage_dir="$bridge_dir/target/xcframework-stage"
header="$bridge_dir/include/manki_anki_rust.h"

if [[ ! -d "$root_dir/Vendor/anki/rslib" ]]; then
  print -u2 "Missing Vendor/anki. Run scripts/bootstrap-anki-rslib.sh first."
  exit 1
fi

if [[ ! -d "$root_dir/Vendor/anki/ftl/core-repo/core" || ! -d "$root_dir/Vendor/anki/ftl/qt-repo/desktop" ]]; then
  print -u2 "Missing Anki translation submodules. Initialize them with:"
  print -u2 "  git -C \"$root_dir/Vendor/anki\" submodule update --init --recursive"
  exit 1
fi

if ! command -v protoc >/dev/null; then
  print -u2 "protoc is required by Anki's protobuf build. Install it, then rerun."
  exit 1
fi

export DESCRIPTORS_BIN="$bridge_dir/target/anki_descriptors.bin"
export IPHONEOS_DEPLOYMENT_TARGET=17.0
mkdir -p "$bridge_dir/target"

for target in aarch64-apple-ios aarch64-apple-ios-sim; do
  # Homebrew's Rust installation does not include non-host standard libraries
  # and cannot install them.  Rustup can provision them; alternatively, allow
  # a custom toolchain where they were installed ahead of time.
  rustlib_dir="$(rustc --print sysroot)/lib/rustlib/$target/lib"
  if [[ ! -d "$rustlib_dir" ]]; then
    if command -v rustup >/dev/null; then
      rustup target add "$target"
    else
      print -u2 "Rust target '$target' is not installed."
      print -u2 "Homebrew Rust cannot add iOS targets. Install rustup, then use its toolchain:"
      print -u2 "  brew install rustup-init"
      print -u2 "  rustup-init -y"
      print -u2 '  export PATH="$HOME/.cargo/bin:$PATH"'
      print -u2 "Restart the shell and rerun this script."
      exit 1
    fi
  fi
  cargo build --manifest-path "$bridge_dir/Cargo.toml" --target "$target" --release
done

print "Building for macOS…"
cargo build --manifest-path "$bridge_dir/Cargo.toml" --release

make_framework() {
  local target="$1"
  local name="$2"
  local platform="$3"
  local framework="$stage_dir/$name/MankiAnkiRust.framework"
    local library
    if [[ "$target" == native ]]; then
      library="$bridge_dir/target/release/libmanki_anki_rust.a"
    else
      library="$bridge_dir/target/$target/release/libmanki_anki_rust.a"
    fi

  rm -rf "$framework"
  mkdir -p "$framework/Headers" "$framework/Modules"
  cp "$library" "$framework/MankiAnkiRust"
  cp "$header" "$framework/Headers/manki_anki_rust.h"
  cat > "$framework/Modules/module.modulemap" <<'MODULEMAP'
framework module MankiAnkiRust {
  header "manki_anki_rust.h"
  export *
}
MODULEMAP
  cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>MankiAnkiRust</string>
  <key>CFBundleIdentifier</key><string>org.manki.AnkiRust</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MankiAnkiRust</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$IPHONEOS_DEPLOYMENT_TARGET</string>
</dict></plist>
PLIST
}

rm -rf "$stage_dir" "$output_dir"
make_framework aarch64-apple-ios ios-device iPhoneOS
make_framework aarch64-apple-ios-sim ios-simulator iPhoneSimulator
make_framework native macos MacOSX

mkdir -p "${output_dir:h}"
xcodebuild -create-xcframework \
  -framework "$stage_dir/ios-device/MankiAnkiRust.framework" \
  -framework "$stage_dir/ios-simulator/MankiAnkiRust.framework" \
  -framework "$stage_dir/macos/MankiAnkiRust.framework" \
  -output "$output_dir"

touch "$stamp_file"
print "Built $output_dir"
