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

# Fetch only the pinned tree instead of cloning Anki's current default branch
# and all of its current submodules before moving backwards to this revision.
# Besides being considerably smaller, retrying the complete shallow checkout
# makes transient GitHub clone failures less likely to break screenshot CI.
for attempt in 1 2 3; do
  rm -rf "$anki_dir"
  mkdir -p "$anki_dir"

  if git -C "$anki_dir" init \
    && git -C "$anki_dir" remote add origin https://github.com/ankitects/anki.git \
    && git -C "$anki_dir" -c http.version=HTTP/1.1 fetch --depth 1 origin "$anki_revision" \
    && git -C "$anki_dir" checkout --detach FETCH_HEAD \
    && git -C "$anki_dir" -c http.version=HTTP/1.1 submodule update --init --depth 1 -- ftl/core-repo ftl/qt-repo; then
    print "Pinned Anki rslib source is ready at $anki_dir"
    exit 0
  fi

  print -u2 "Anki checkout attempt $attempt failed."
  if (( attempt < 3 )); then
    sleep $((attempt * 5))
  fi
done

print -u2 "Unable to prepare pinned Anki sources after 3 attempts."
exit 1
