# Working in this repo

Intervals is an iPhone app that runs interval timers and stretch routines. It keeps cueing with the screen locked and lowers other apps' music for each cue. It is installed with AltStore, not the App Store.

## Layout

| Path | What lives there |
| --- | --- |
| `IntervalCore/` | Pure Swift package, Foundation only. Workouts, the compiled timeline, `Session`, the cue schedule, the library file, the history. All timer logic is here. |
| `App/` | The SwiftUI app. `RunModel` is the only writer of the session. `LibraryStore` and `HistoryStore` are the only writers of their files. `Audio/` holds `CuePlayer`, `SoundBank`, `HeadphoneRemote`. `Views/` holds the screens and `Theme`. |
| `AppTests/` | Tests that need the iOS runtime. |
| `AppUITests/` | End-to-end flows. They attach a named screenshot at each step. |
| `Scripts/` | Test, build and release scripts. |
| `project.yml` | The XcodeGen spec. `IntervalTracker.xcodeproj` is generated from it and committed. |
| `docs/design.md` | Why the timer and the audio work the way they do. Read it before you change either. |

## Commands

```sh
Scripts/test-core.sh                      # timer logic, any Mac
xcodegen generate --spec project.yml      # after adding or removing a file
xcodebuild test -project IntervalTracker.xcodeproj -scheme IntervalTracker \
	-destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' CODE_SIGNING_ALLOWED=NO
Scripts/build-ipa.sh                      # unsigned .ipa at build/Intervals.ipa
```

CI builds with an older Xcode than a local machine may have. Use no API newer than iOS 17. The app targets build in Swift 5 language mode. The package builds in Swift 6 mode.

## Every merge must reach AltStore

The owner updates the app from AltStore. A merge that changes the app must show up there as an update with no manual step.

- The AltStore source is `https://github.com/Kron00/interval-tracker/releases/latest/download/altstore.json`. Never move it or rename the asset.
- On every push to `main`, the `release` job in `.github/workflows/ci.yml` runs the package tests and then `Scripts/release-on-merge.sh`. It builds an unsigned `.ipa`, creates a GitHub release, and attaches the source JSON that `Scripts/altstore-source.py` builds from every release.
- The release job does not wait for the simulator tests. They are slow and timing-sensitive on CI, and a slow runner once kept a merged change out of AltStore. The simulator tests gate the pull request, so do not merge a pull request whose checks are not green.
- The version is the major.minor in `project.yml` plus the commit count, for example `1.2.31`. Raise the major.minor in `project.yml` when a change deserves it. Do not edit version numbers anywhere else.
- AltStore compares `version` and `buildVersion` in the source with the installed app. Each release body ends with a `Build: N` line that records the build number. Keep that line.
- AltStore refuses to install an app whose entitlements or privacy keys differ from the source. If you add an entitlement, an app extension, or a `UsageDescription` key, update `appPermissions` in `Scripts/altstore-source.py` in the same change.
- After a merge, check that the release exists and that the source URL and the `.ipa` URL both return 200 without signing in.
- To publish by hand from a pushed commit, run `Scripts/release.sh <version> "<notes>"`.

## Rules the code depends on

- **Time comes from one anchor date.** `Session` stores when elapsed time was zero and derives everything else. Never count ticks. Never store a flag for a state you can derive, such as finished or waiting.
- **The cue schedule is data.** The package decides what sounds when. `CuePlayer` only plays it. Timing constants live in `CueTiming`.
- **Interval timers advance by themselves. A stretch routine waits before every stretch.** A timed hold waits for Start, then its count-in and its hold run by themselves, and the next stretch waits. A rep stretch is not timed and waits for Next. A routine has no automatic gaps between stretches. The last timed hold finishes the workout by itself. During a wait, a single headphone press means Start or Next.
- **Nothing on the run screen moves when its state changes.** It is fixed-height slots around the clock. `testNothingMovesWhenTheRunChangesState` compares frames. Add new states to that test.
- **The run screen redraws once a second, and not at all while waiting or paused.** Do not animate the clock digits. A rolling digit transition cost 71% of one core.
- **Speech never runs on the main thread.** A voice lookup there froze the app.
- **`CuePlayer.reconcile` runs ten times a second.** Keep its early return free of allocation.
- **Every screen is dark.**
- **A released library file must keep loading.** If you change the file format, decode the shapes that released versions wrote. The same holds for the history file.
- **The history is its own file.** `history.json` is apart from `library.json`. A history file that cannot be read is set aside, and it must never cost the saved workouts. Do not move the history into the library file.
- **A run is reported once, and never while Undo can bring it back.** `RunModel` reports from `end()` and from its tick, and never from `change`. `History.add` decides what is kept. `docs/design.md` has the reasons.
- **The package takes dates and calendars as arguments.** Nothing in `IntervalCore` reads the clock or the calendar of the phone.
- Validate at the boundary only: the failable initialisers in the package and the `Decodable` code. Editors hold plain drafts and convert on Save.

## What a simulator cannot prove

Locked-screen playback, music ducking, and headphone presses need a real iPhone. Do not claim they work from a simulator run. Settings has an audio check, a headphone check, three ducking methods, and a log for checking them on a phone. Keep those working.

## How to verify a change

1. Run `Scripts/test-core.sh` and the full `xcodebuild test`.
2. Export the UI test screenshots and look at them. Passing tests do not show a clipped label or a layout that jumps.

	```sh
	xcrun xcresulttool export attachments --path build/Result.xcresult --output-path build/screenshots
	python3 Scripts/name-screenshots.py build/screenshots
	```

3. For anything that affects a running timer, measure CPU for the app's process in the simulator. A running timer uses about 3% of one core in a Debug build.
4. Say plainly what you could not verify.

## Style

- Comments explain a why the code cannot show. No narration and no section banners.
- Tests assert what a user or caller can observe. Derive expected values from the requirement, not from a run of the code.
- Commit subjects are plain sentences. The body explains why.
- Do not put personal details in the repo, the PRs, or the release notes. The repo is public.
