#!/bin/zsh
set -euo pipefail

ROOT="/Users/lazynius/Desktop/MacMini/Nueva/Glowsy"
mkdir -p /tmp/swift-module-cache /tmp/clang-module-cache
SWIFT_MODULECACHE_PATH=/tmp/swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
swift "$ROOT/scripts/generate_moments_media_pdf.swift"
