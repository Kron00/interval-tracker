# Working in this repo

Intervals is an iPhone app that runs interval timers and stretch routines. It keeps cueing with the screen locked and lowers other apps' music for each cue. A Live Activity shows the run on the lock screen and in the Dynamic Island. It can build a workout from a description, with ChatGPT. It is installed with AltStore, not the App Store.

## Layout

| Path | What lives there |
| --- | --- |
| `IntervalCore/` | Pure Swift package, Foundation only. Workouts, the compiled timeline, `Session`, the cue schedule, the library file, the history, and `WorkoutBlueprint`, which turns a model's answer into a workout. All timer logic is here. |
| `App/` | The SwiftUI app. `RunModel` is the only writer of the session. `LibraryStore` and `HistoryStore` are the only writers of their files. `Audio/` holds `CuePlayer`, `SoundBank`, `HeadphoneRemote`. `Views/` holds the screens and `Theme`. `LiveActivityController` starts, updates and ends the Live Activity. |
| `App/ChatGPT/` | The ChatGPT sign-in and the request for a workout. `ChatGPTAccount` owns the Keychain and the tokens. `LoopbackCallback` is the listener on 127.0.0.1. `WorkoutGenerator` talks to the Responses API. `ChatGPTModel` is what the screens observe. `StubOpenAI` stands in for OpenAI in UI tests. |
| `Widgets/` | The `IntervalTrackerWidgets` app extension. It draws the Live Activity and nothing else. |
| `Shared/` | The one file that both the app and the extension compile: what the Live Activity shows, the tap it hands back, and the phase colours. |
| `AppTests/` | Tests that need the iOS runtime. |
| `AppUITests/` | End-to-end flows. They attach a named screenshot at each step. |
| `Scripts/` | Test, build and release scripts. |
| `project.yml` | The XcodeGen spec. `IntervalTracker.xcodeproj` is generated from it and committed. |
| `docs/design.md` | Why the timer, the audio, and the ChatGPT sign-in work the way they do. Read it before you change any of them. |

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
- AltStore refuses to install an app whose entitlements or privacy keys differ from the source. The app and its extension have no entitlements and no `UsageDescription` keys, so `appPermissions` in `Scripts/altstore-source.py` is empty. If you add an entitlement, another app extension, or a `UsageDescription` key, update `appPermissions` in the same change. Read the keys from the built `Info.plist` files, not from `project.yml`.
- iOS refuses to install an app whose extension has a different version from the app. Both targets take `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from the project settings, and `Scripts/release.sh` checks both `Info.plist` files. Never set a version on one target.
- The bundle identifier of the extension must start with the bundle identifier of the app.
- AltStore may remove app extensions when it installs. The app must run without its extension. Nothing but the Live Activity may depend on the extension.
- `Scripts/release-on-merge.sh` releases only when a folder it lists has changed. If you add a folder that the app is built from, add it to that list.
- After a merge, check that the release exists and that the source URL and the `.ipa` URL both return 200 without signing in.
- To publish by hand from a pushed commit, run `Scripts/release.sh <version> "<notes>"`.

## Rules the code depends on

- **Time comes from one anchor date.** `Session` stores when elapsed time was zero and derives everything else. Never count ticks. Never store a flag for a state you can derive, such as finished or waiting.
- **The cue schedule is data.** The package decides what sounds when. `CuePlayer` only plays it. Timing constants live in `CueTiming`.
- **The heads-up is one rule.** `Timeline.headsUp(in:_:)` decides which phase says "Get ready" and when. The voice cue and `RunProgress.isHeadsUp` both come from it. The app reads `isHeadsUp` and never works out the time itself. Only an interval timer has one. The count-in of a stretch also reads "Get ready", and it is not a heads-up.
- **Interval timers advance by themselves. A stretch routine waits before every stretch.** A timed hold waits for Start, then its count-in and its hold run by themselves, and the next stretch waits. A rep stretch is not timed and waits for Next. A routine has no automatic gaps between stretches. The last timed hold finishes the workout by itself. During a wait, a single headphone press means Start or Next.
- **Nothing on the run screen moves when its state changes.** It is fixed-height slots around the clock. `testNothingMovesWhenTheRunChangesState` compares frames. Add new states to that test.
- **The run screen redraws once a second, and not at all while waiting or paused.** Do not animate the clock digits. A rolling digit transition cost 71% of one core.
- **Speech never runs on the main thread.** A voice lookup there froze the app.
- **`CuePlayer.reconcile` runs ten times a second.** Keep its early return free of allocation.
- **The app never updates the Live Activity on a timer.** iOS ticks the countdown from the two dates of the phase. `LiveActivityController.reconcile` sends an update only when the content state differs from the last one, so every field of that state must stay the same for a whole phase. Take dates from `Session.phaseEnd(at:)`, never from `now`.
- **One task talks to ActivityKit.** Updates are async. Do not start a second task for one, or two updates can land out of order.
- **`LiveActivityController.swift` is the only file in the app that imports ActivityKit.** Guard every call. A user can turn Live Activities off, and the extension can be missing.
- **The extension does not import `IntervalCore`.** The app sends it plain values. A decision about a run belongs in the package, and a text or a colour key belongs in the content state.
- **The button on the card is a headphone press.** `AdvanceRunIntent` is compiled into both targets, and iOS runs it in the app. It hands `RunModel.advance(fromWait:)` the number its card was drawn with, which `RunModel` replaces with every change to the run. That function does nothing unless the number is still the newest and the run waits, and then calls `RunModel.handle`. Change a session from the card in no other way. The intent must keep working with no entitlement and no app group.
- **Every screen is dark.**
- **A released library file must keep loading.** If you change the file format, decode the shapes that released versions wrote. The same holds for the history file.
- **The history is its own file.** `history.json` is apart from `library.json`. A history file that cannot be read is set aside, and it must never cost the saved workouts. Do not move the history into the library file.
- **A run is reported once, and never while Undo can bring it back.** `RunModel` reports from `end()` and from its tick, and never from `change`. `History.keeps` decides what is kept, for `History.add` and for the line in the End dialog. Do not repeat its rule anywhere. `docs/design.md` has the reasons.
- **The package takes dates and calendars as arguments.** Nothing in `IntervalCore` reads the clock or the calendar of the phone.
- Validate at the boundary only: the failable initialisers in the package and the `Decodable` code. Editors hold plain drafts and convert on Save.
- **A model's answer becomes a workout in one function.** `WorkoutBlueprint.workout()` is the only code that maps model output to a `Workout`. The schema and the instructions sit beside it. The model never chooses the count-in of a routine.
- **No test or script in CI contacts OpenAI.** Tests pass a stub as `OpenAITransport`. UI tests launch the app with `-aiStub signedIn` or `-aiStub signedOut`, which swaps in `StubOpenAI` and an in-memory vault. `-aiStubReplies` lists what the stub gives the descriptions in turn: `answer`, `never` or `busy`. Never sign in from a test.
- **Try again and Edit never cost the answer on the screen.** `DescribeState` carries the answer through a retry, and the editor opens over the result. A cancel or a failure must lead back to the answer.
- **Tokens and the API key live in the Keychain only**, as one `Vault`. Never log a token, a sign-in code, or the key. Derive the account state from the vault. Do not store it.
- **One token refresh at a time.** Every refresh kills the old refresh token, so every caller waits for the refresh in `ChatGPTAccount`. Do not refresh anywhere else.
- **The sign-in follows OpenAI's documented flow for open-source apps.** Do not use the Codex CLI's client id or `chatgpt.com/backend-api`. The redirect address must stay `http://127.0.0.1:<port>/auth/callback`, and the listener must stay bound to 127.0.0.1.
- Do not write `try result.get()`. In a hosted test it threw an unrelated error left over from an earlier `try?` in place of the result's own failure. Use a `switch`.

## What a simulator cannot prove

Locked-screen playback, music ducking, and headphone presses need a real iPhone. So do three things about the Live Activity: whether its alert lights a locked phone, whether AltStore installs the extension, and whether the count-in sounds after **Start** on the card of a phone that has suspended the app. Do not claim they work from a simulator run. Settings has an audio check, a headphone check, three ducking methods, a Live Activity status line, and a log for checking them on a phone. Keep those working.

The simulator does draw the lock screen and the Dynamic Island. Three UI tests lock it and read the Live Activity there, and one of them taps the button on the card.

The ChatGPT feature needs a real account, and the sign-in sheet needs a real iPhone. The simulator proves the sheet, the listener, and every request against stand-ins. `LiveOpenAITests` runs the app's own sign-in and generation against OpenAI. It is skipped unless `TEST_RUNNER_LIVE_OPENAI=1` is set, and it needs a person to open the address it prints, so run it when you change a request. Nobody has signed in from the app on a phone. `docs/design.md` lists what is unproven. The Keychain tests run only in a signed build, so run them once without `CODE_SIGNING_ALLOWED=NO` when you change `KeychainVaultStore`.

## How to verify a change

1. Run `Scripts/test-core.sh` and the full `xcodebuild test`.
2. Export the UI test screenshots and look at them. Passing tests do not show a clipped label or a layout that jumps. Screenshots 50 to 59 are the lock screen and the Dynamic Island.

	```sh
	xcrun xcresulttool export attachments --path build/Result.xcresult --output-path build/screenshots
	python3 Scripts/name-screenshots.py build/screenshots
	```

3. For anything that affects a running timer, measure CPU for the app's process in the simulator. A running timer uses about 3% of one core in a Debug build. Pick the process by the simulator's device identifier in its path, because another simulator may run the same app.
4. For anything that changes a target or `project.yml`, run `Scripts/build-ipa.sh` and check that `build/ipa/Payload/IntervalTracker.app/PlugIns/IntervalTrackerWidgets.appex` exists.
5. Say plainly what you could not verify.

## Style

- Comments explain a why the code cannot show. No narration and no section banners.
- Tests assert what a user or caller can observe. Derive expected values from the requirement, not from a run of the code.
- Commit subjects are plain sentences. The body explains why.
- Do not put personal details in the repo, the PRs, or the release notes. The repo is public.
