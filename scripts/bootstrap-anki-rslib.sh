#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
root_dir=${script_dir:h}
vendor_dir="$root_dir/Vendor"
anki_dir="$vendor_dir/anki"

# Amgi pins this exact Anki revision. Keeping the revision here makes the Rust
# and generated-protobuf APIs reproducible rather than tracking Anki main.
anki_revision="e64c6b1aee3e8d668fb8bbe084beada8e070d985"

if [[ -e "$anki_dir" ]]; then
  print -u2 "Refusing to overwrite existing $anki_dir"
  exit 1
fi

mkdir -p "$vendor_dir"
git clone --recurse-submodules https://github.com/ankitects/anki.git "$anki_dir"
git -C "$anki_dir" checkout --detach "$anki_revision"
git -C "$anki_dir" submodule update --init --recursive

print "Pinned Anki rslib source is ready at $anki_dir"
