#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x "build/Tiny Vinyl.app/Contents/MacOS/TinyVinyl" ]; then
  /bin/bash build.sh
fi
open "build/Tiny Vinyl.app"
