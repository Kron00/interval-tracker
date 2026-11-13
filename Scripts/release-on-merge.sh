#!/bin/sh
# Run by CI after the tests pass on main. Publishes a release when the app changed since the last
# one, so every merge that changes the app shows up in AltStore as an update.
#
# The version is the major.minor from project.yml plus the commit count, for example 1.2.31.
set -e
cd "$(dirname "$0")/.."
REPO=Kron00/interval-tracker
git fetch -q --tags origin

LAST=$(gh release list --repo "$REPO" --exclude-drafts --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName')
if [ -n "$LAST" ] && git diff --quiet "$LAST" HEAD -- App IntervalCore/Sources project.yml; then
  echo "No change to the app since $LAST. Nothing to release."
  exit 0
fi

BASE=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
[ -n "$BASE" ] || { echo "project.yml has no MARKETING_VERSION." >&2; exit 1; }
exec Scripts/release.sh "$BASE.$(git rev-list --count HEAD)" "$(git log -1 --format=%s)"
