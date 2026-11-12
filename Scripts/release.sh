#!/bin/sh
# Publishes a version for AltStore: builds an unsigned .ipa from the pushed HEAD commit, creates the
# GitHub release, and attaches the AltStore source JSON that lists every release.
#
# Usage: Scripts/release.sh 1.1 "What changed in this version"
set -e
cd "$(dirname "$0")/.."
VERSION="$1"
NOTES="$2"
[ -n "$VERSION" ] && [ -n "$NOTES" ] || { echo "usage: $0 <version> <notes>" >&2; exit 2; }

REPO=Kron00/interval-tracker
TAG="v$VERSION"
SHA=$(git rev-parse HEAD)
BUILD=$(git rev-list --count HEAD)
git fetch -q origin
git branch -r --contains "$SHA" | grep -q . || { echo "Push $SHA first: the release tag must point at a pushed commit." >&2; exit 1; }
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && { echo "$TAG already exists." >&2; exit 1; }

# A separate checkout of the commit, so uncommitted work in this folder can never end up in a release.
SRC=build/release-src
git worktree remove --force "$SRC" 2>/dev/null || true
git worktree add -q --detach "$SRC" "$SHA"
trap 'git worktree remove --force "$SRC"' EXIT

xcodebuild build -project "$SRC/IntervalTracker.xcodeproj" -scheme IntervalTracker -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/release-derived \
  CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" -quiet
OUT=build/release
rm -rf "$OUT" && mkdir -p "$OUT/Payload"
cp -R build/release-derived/Build/Products/Release-iphoneos/IntervalTracker.app "$OUT/Payload/"
BUILT=$(plutil -extract CFBundleShortVersionString raw "$OUT/Payload/IntervalTracker.app/Info.plist")
[ "$BUILT" = "$VERSION" ] || { echo "The .ipa says version $BUILT, expected $VERSION." >&2; exit 1; }
(cd "$OUT" && zip -qry Intervals.ipa Payload)

gh release create "$TAG" "$OUT/Intervals.ipa" --repo "$REPO" --target "$SHA" --draft \
  --title "Intervals $VERSION" --notes "$NOTES

Build: $BUILD" >/dev/null
python3 Scripts/altstore-source.py --pending "$TAG" > "$OUT/altstore.json"
gh release upload "$TAG" "$OUT/altstore.json" --repo "$REPO" --clobber
gh release edit "$TAG" --repo "$REPO" --draft=false --latest >/dev/null

for url in "https://github.com/$REPO/releases/latest/download/altstore.json" \
           "https://github.com/$REPO/releases/download/$TAG/Intervals.ipa"; do
  echo "$(curl -s -o /dev/null -L -w '%{http_code}' "$url") $url"
done
