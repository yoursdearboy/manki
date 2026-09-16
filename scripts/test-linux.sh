#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# Package.swift deliberately contains only platform-independent production
# code on Linux, keeping the quick agent test suite independent of Xcode.
swift test
