<img src="assets/icon.svg" width="64" height="64" alt="">

# Interval Tracker

An interval timer for iPhone. You build timers from a warm-up, work and rest rounds, and a cool-down. The app beeps, counts down, and speaks at each phase change. It keeps doing that with the screen locked, and it lowers your music for each cue without stopping it.

Two presets are built in:

| Preset | Warm-up | Rounds | Cool-down | Total |
| --- | --- | --- | --- | --- |
| Norwegian 4x4 | 5:00 | 4 × 4:00 work, 3:00 rest | 5:00 | 38:00 |
| 20/20 HIIT | 5:00 | 9 × 0:20 work, 0:20 rest | 3:00 | 14:00 |

Both presets rest after every round, including the last. To drop the last rest, duplicate the preset and turn off **Rest after last round**.

## Install the app on your iPhone

You do these steps once. You need a Mac with about 25 GB free, an Apple Account, and a cable.

1. Install Xcode from the Mac App Store. Open it, accept the license, and let it install the iOS platform when it offers.
2. In Xcode, open **Settings**, then **Accounts**. Click **+** and sign in with your Apple Account.
3. Get the code and open the project.

	```sh
	git clone https://github.com/Kron00/interval-tracker.git
	open interval-tracker/IntervalTracker.xcodeproj
	```

4. In the project navigator, click **IntervalTracker**, then the **IntervalTracker** target, then **Signing & Capabilities**. Set **Team** to your name. If Xcode says the bundle identifier is not available, change `com.kron00.IntervalTracker` to any identifier of your own.
5. Connect the iPhone with the cable and unlock it. Tap **Trust** on the phone.
6. On the iPhone, open **Settings**, then **Privacy & Security**, then **Developer Mode**. Turn it on and restart the phone when asked.
7. In the Xcode toolbar, choose your iPhone as the run destination. Press Cmd-R.
8. If the phone refuses to open the app, open **Settings**, then **General**, then **VPN & Device Management** on the phone. Tap your developer certificate, then **Trust**.

The app is named **Intervals** on the home screen.

With a free Apple Account the app stops opening after 7 days. Connect the phone and press Cmd-R again to renew it. Your saved timers stay on the phone. A paid Apple Developer membership extends the 7 days to one year.

## Check the audio on your phone

Nobody has run this app on a real iPhone yet. The timer, the screens, and the sounds are tested in the simulator. Two behaviors exist only on a phone: whether the app stays awake while locked, and whether your music dips and comes back. The app has a 1-minute check for both.

1. Start your music.
2. In Intervals, tap the gear, then **Run 1-minute audio check**.
3. Lock the phone and listen.

| You hear | It means |
| --- | --- |
| Three beeps, a tone, and "Round one" at 0:27 | The app stays awake while locked. |
| Nothing after the first tone | iOS suspended the app. Copy the audio log from Settings and report it. |
| The music dips for each cue and returns to full between cues | Ducking works. Change nothing. |
| The music stays low after a cue | In Settings, choose **Dip, then restart audio** and run the check again. |
| The music never dips, or the cues are hard to hear | In Settings, choose **Low for the whole run**. |

## Run the tests

`Scripts/test-core.sh` runs the timer logic tests on any Mac, with or without Xcode.

The app tests and the UI tests need Xcode and a simulator:

```sh
xcodebuild test -project IntervalTracker.xcodeproj -scheme IntervalTracker \
	-destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

CI runs both on every push, plus a build for the device architecture. The UI test attaches a screenshot of each screen, and CI uploads the screenshots as the `test-results` artifact.

## Change the project

`project.yml` is the source of the Xcode project. After you add or remove a file outside Xcode, run `xcodegen generate` and commit the result.

[docs/design.md](docs/design.md) explains how the timer keeps time and how the cues are scheduled.
