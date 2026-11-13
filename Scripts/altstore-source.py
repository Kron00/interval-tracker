"""Prints the AltStore source JSON for this app, built from the repo's GitHub releases.

Every published release that carries Intervals.ipa becomes one version, newest first. AltStore
compares the first version's `version` and `buildVersion` with the installed app, so each release
body ends with a "Build: N" line that records the CFBundleVersion of its .ipa.

Usage: altstore-source.py [--pending TAG]   (TAG names a draft release to list as if published)
"""
import json
import re
import subprocess
import sys

REPO = "Kron00/interval-tracker"
IPA = "Intervals.ipa"
BUNDLE_ID = "com.kron00.IntervalTracker"
ICON_PATH = "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# AltStore refuses an app whose privacy keys differ from these. Read them from the built Info.plist.
PRIVACY = {
    "NSBluetoothAlwaysUsageDescription":
        "Intervals reads your heart rate from a Bluetooth heart-rate monitor, such as a Fitbit Air, during a workout.",
}

pending = sys.argv[2] if len(sys.argv) == 3 and sys.argv[1] == "--pending" else None
pages = json.loads(subprocess.run(
    ["gh", "api", f"repos/{REPO}/releases", "--paginate", "--slurp"], check=True, capture_output=True, text=True).stdout)
releases = [release for page in pages for release in page]

versions = []
for release in releases:
    tag = release["tag_name"]
    listed = tag == pending or not (release["draft"] or release["prerelease"])
    asset = next((a for a in release["assets"] if a["name"] == IPA), None)
    build = re.search(r"^Build: (\d+)\s*$", release["body"] or "", re.MULTILINE)
    if not (listed and asset and build):
        continue
    notes = re.sub(r"\n*^Build: \d+\s*$", "", release["body"], flags=re.MULTILINE).strip()
    versions.append({
        "version": tag.removeprefix("v"),
        "buildVersion": build.group(1),
        "date": release["published_at"] or release["created_at"],
        "localizedDescription": notes,
        "downloadURL": f"https://github.com/{REPO}/releases/download/{tag}/{IPA}",
        "size": asset["size"],
        "minOSVersion": "17.0",
    })

if not versions:
    sys.exit("No release carries Intervals.ipa and a 'Build: N' line.")

versions.sort(key=lambda v: [int(part) for part in v["version"].split(".")], reverse=True)
icon = f"https://raw.githubusercontent.com/{REPO}/v{versions[0]['version']}/{ICON_PATH}"
description = (
    "Interval timers and stretch routines for iPhone. It beeps, counts down and speaks at each "
    "change, keeps going with the screen locked, and lowers your music for each cue.")
print(json.dumps({
    "name": "Intervals",
    "subtitle": "Interval timer that keeps cueing while locked",
    "description": description,
    "iconURL": icon,
    "website": f"https://github.com/{REPO}",
    "tintColor": "#10B981",
    "nsfw": False,
    "featuredApps": [BUNDLE_ID],
    "apps": [{
        "name": "Intervals",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": "Kron00",
        "subtitle": "Interval timer that keeps cueing while locked",
        "localizedDescription": description,
        "iconURL": icon,
        "tintColor": "#10B981",
        "category": "utilities",
        "versions": versions,
        "appPermissions": {"entitlements": [], "privacy": PRIVACY},
    }],
    "news": [],
}, indent=2))
