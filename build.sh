#!/usr/bin/env bash
# Build RAD DRIFT: no-libc Zig -> wasm32-freestanding -> web/raddrift.wasm
set -euo pipefail
cd "$(dirname "$0")"
zig build-exe src/main.zig \
  -target wasm32-freestanding \
  -O ReleaseFast \
  -fno-entry -rdynamic \
  -femit-bin=web/raddrift.wasm
echo "built web/raddrift.wasm ($(stat -c%s web/raddrift.wasm) bytes)"
