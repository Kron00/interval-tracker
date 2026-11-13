#!/bin/sh
# Runs the IntervalCore tests. Plain `swift test` cannot find the Testing framework on a Mac
# that has Command Line Tools but no Xcode, so that case needs the search paths spelled out.
cd "$(dirname "$0")/.." || exit 1
if xcodebuild -version >/dev/null 2>&1; then
  exec swift test --package-path IntervalCore "$@"
fi
CLT=/Library/Developer/CommandLineTools
FRAMEWORKS=$CLT/Library/Developer/Frameworks
exec swift test --package-path IntervalCore \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib" "$@"
