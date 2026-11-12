#!/bin/sh
# Builds an unsigned Release .ipa for AltStore, which signs it with your Apple Account when it installs.
set -e
cd "$(dirname "$0")/.."
xcodebuild build -project IntervalTracker.xcodeproj -scheme IntervalTracker -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO -quiet
rm -rf build/ipa build/Intervals.ipa
mkdir -p build/ipa/Payload
cp -R build/DerivedData/Build/Products/Release-iphoneos/IntervalTracker.app build/ipa/Payload/
(cd build/ipa && zip -qry ../Intervals.ipa Payload)
echo "$(pwd)/build/Intervals.ipa"
