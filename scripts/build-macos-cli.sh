#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
root_dir=${script_dir:h}
output_dir="$root_dir/.build"
framework_dir="$root_dir/Frameworks/MankiAnkiRust.xcframework/macos-arm64/MankiAnkiRust.framework"
stamp_file="$root_dir/Frameworks/.manki-anki-rust.stamp"

needs_framework_build=false
if [[ ! -d "$framework_dir" || ! -f "$stamp_file" || ! -d "$root_dir/Vendor/anki" ]]; then
  needs_framework_build=true
elif [[ -n "$(find "$root_dir/AnkiRustBridge" "$root_dir/Vendor/anki" \
  "$script_dir/build-anki-xcframework.sh" -type f -newer "$stamp_file" -print -quit)" ]]; then
  needs_framework_build=true
fi

if [[ "$needs_framework_build" == true ]]; then
  if [[ ! -d "$root_dir/Vendor/anki/rslib" ]]; then
    print -u2 "Missing Vendor/anki. Run scripts/bootstrap-anki-rslib.sh first."
    exit 1
  fi
  if ! command -v protoc >/dev/null; then
    print -u2 "protoc is required by Anki's protobuf build. Install it, then rerun."
    exit 1
  fi
  "$script_dir/build-anki-xcframework.sh"
else
  print "Reusing $root_dir/Frameworks/MankiAnkiRust.xcframework"
fi

if [[ ! -d "$framework_dir" ]]; then
  print -u2 "macOS framework slice was not created at $framework_dir"
  exit 1
fi

mkdir -p "$output_dir"
CLANG_MODULE_CACHE_PATH="$output_dir/clang-module-cache" swiftc \
  -parse-as-library \
  -F "${framework_dir:h}" \
  -framework MankiAnkiRust \
  "$root_dir/MankiCLI/MankiCLI.swift" \
  -o "$output_dir/manki-anki-cli"
print "Built $output_dir/manki-anki-cli"
