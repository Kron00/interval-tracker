# About the design

## Why the timer never counts ticks

iOS suspends a backgrounded app within seconds, and timers that do fire can fire late. A timer that adds one second per tick falls behind every time that happens.

A `Session` stores one date instead: the moment at which elapsed time would be zero. Everything on the run screen is computed from `now` minus that date. Pause stores the elapsed time. Resume, skip, and restart move the date. "Finished" is not a stored state, so nothing has to notice the end and set a flag while the app is suspended.

`Session` lives in the `IntervalCore` package, which imports only Foundation. That is why its tests run on a Mac with no simulator.

## Why a stretch routine is not a second engine

A `Workout` has a name and a `Plan`. The plan is either `.intervals` or `.routine`. `Timeline` turns either plan into the same list of segments, and it is the only code that asks which kind of plan it has. `Session`, the cue schedule, the audio, and the run screen work on segments and never ask.

A routine becomes these segments:

| Stretch | Segments |
| --- | --- |
| Done once | get ready, hold |
| Done on each side | get ready, hold left, switch sides, hold right |

The two gaps are ordinary segments with their own length, so the clock, skip, and the strip need nothing new for them. Daily Stretch has 10 stretches, 4 of them on each side. That makes 28 segments and 10:45.

A stretch that counts reps is still a timed hold. Ten reps at 5 seconds each is a 50-second hold, so a routine never waits for a tap.

Each segment is one `Phase`. A phase knows its own title, caption, colour family, how-to link, and spoken words. The run screen reads those and draws them. It does not know which kind of workout it shows.

Two rules treat a gap as part of the hold it leads into. Restart from a hold goes back to the start of the gap before it, so the app names the stretch again and you have time to get into position. "Up next" names the next hold and skips the gap before it.

## Why the cue schedule is data

`Session.cueSchedule` returns every sound of the run with the date it plays, grouped into `DuckWindow`s. A window is one stretch of lowered music and the sounds inside it. The package decides what sounds when and how long the music stays low. The app only executes the schedule.

For one phase change at time T:

| When | What |
| --- | --- |
| T − 3.5 s | Music dips |
| T − 3, T − 2, T − 1 s | Countdown beeps |
| T | Phase tone |
| T + 0.5 s | Voice, in its slot |
| End of the slot + 0.2 s | Music returns |

All of these numbers are in `CueTiming` in `Cues.swift`.

### How long a spoken phrase may be

An interval timer speaks a fixed set of phrases. A routine speaks the names its user typed. The schedule still has to know how long each phrase lasts, and it cannot ask the speech engine, because the package has none.

So the slot comes from the text alone. It is 0.4 s plus 0.06 s for each character, rounded up to a tenth of a second, and never below 1.5 s or above 4.0 s. Every interval phrase is short enough to get 1.5 s, which is what it had before routines existed. "Hip Flexor Couch Stretch, left side" gets 2.5 s.

Three limits follow from the slot:

- A stretch name is 40 characters at most. With ", left side" added, its slot is 3.5 s.
- The get-ready gap is 0:05 at least. The voice starts 0.5 s into the gap, so every name fits its gap and is always spoken.
- No countdown beep sounds before the voice has finished.

`SoundBank` renders each phrase to a buffer before the run and must deliver a buffer no longer than the slot. If the rendered speech runs long, `SoundBank` renders it once more at a faster rate. If the speech still runs long, `SoundBank` cuts it at the slot and writes a line to the audio log. In the simulator, all twelve Daily Stretch phrases fit at normal speed. The closest is "Hip Flexor Couch Stretch, left side" at 2.48 s of 2.5 s. A phone may use a different voice, so that margin is not proven there.

### What a stretch boundary sounds like

Hip Flexor Couch Stretch ends at T and Pigeon follows. The get-ready gap is 8 s.

| When | What |
| --- | --- |
| T − 3.5 s | Music dips |
| T − 3, T − 2, T − 1 s | Countdown beeps |
| T | Phase tone. The screen shows PIGEON and "Get ready · Left side" |
| T + 0.5 s | Voice: "Pigeon, left side" |
| T + 2.2 s | Music returns |
| T + 4.5 s | Music dips |
| T + 5, T + 6, T + 7 s | Countdown beeps |
| T + 8 s | Phase tone. The hold starts with no voice, because the gap already named it |
| T + 8.6 s | Music returns |

A switch-sides gap is 5 s, which is too short for the music to come back in the middle. The music dips 3.5 s before the left side ends and returns 0.6 s after the right side starts. In between are the countdown, the tone, "Switch sides", a second countdown, and the tone that starts the right side.

A hold that counts reps has a soft beat at the start of each rep after the first, and no countdown. The music stays low for the whole hold. Dipping it again for every rep would be worse than leaving it low.

## How cues keep playing while the phone is locked

Three things have to hold.

- **The app stays awake.** The `audio` background mode keeps an app running only while its audio is running. `CuePlayer` loops a silent buffer for the whole run.
- **Beeps do not depend on timers.** `CuePlayer` queues every remaining sound on an `AVAudioPlayerNode` at an exact host time. The audio thread plays them. Voice phrases are rendered to buffers before the run starts, so a voice cue is queued the same way as a beep.
- **Recovery is one code path.** `RunModel` calls `CuePlayer.reconcile` ten times a second with what the run needs: nothing, a paused run, or a schedule to play. `reconcile` compares that with what it last queued and repairs any difference. A route change or a skip only marks the queued state as unknown, and the next call rebuilds it.

## Why headphone controls need a second audio mode

iOS sends a headphone press to one app, the one it shows on the lock screen as Now Playing. An app whose audio mixes with other apps is never that app. So lowering your music under a cue and receiving a press cannot both happen in the same run.

`CuePlayer.sharing` holds the choice. The Headphone controls setting picks it.

| | Mixing | Exclusive |
| --- | --- | --- |
| Setting | Headphone controls off | Headphone controls on |
| Other apps' audio | Keeps playing and dips for each cue | Stops for the whole run |
| Headphone presses | Go to the music app | Come to this app |
| Paused | Audio stops and the music is released | Audio is kept for 15 minutes |
| A call, or another app starts to play | Audio is rebuilt when it can be | The run pauses |

Mixing behaves as the app did before headphone controls existed.

Two parts of exclusive mode need a reason.

- **A paused run keeps its audio.** With no audio, iOS suspends the app, and a suspended app cannot receive the press that would resume it. So the engine and the silent loop keep running while paused, with no cue queued. After 15 minutes `CuePlayer` gives the audio up, so a forgotten workout does not hold it all day.
- **An interruption pauses the run and the app does not take the audio back.** Mixing retries every second, which is harmless when audio mixes. In exclusive mode a retry would cut off the call, or stop the music you just started in another app. The run resumes when iOS reports that the interruption ended and playback should resume, or when you tap Resume.

`HeadphoneRemote` is the only file that imports MediaPlayer. It publishes the current phase to the lock screen and turns the five remote commands into `RunCommand` values. `Session.perform` decides what each command does, so that part is tested on a Mac. `RunModel` only forwards the command and reconciles.

## Why nothing on the run screen moves

The phone sits on the floor and you read it at a glance. If the clock moved every time you paused, you would have to find it again.

So every block on the run screen has a fixed height and the clock takes the space that is left. A line with nothing to say still takes its line. The Undo and How to buttons appear inside a row that is always there. A state change swaps what is drawn inside a block, with a fade of a quarter of a second, and never changes where a block is. A UI test records where the title, the clock, the total, and two buttons are, and fails if any of them is somewhere else after a pause, a resume, a skip, or a change of phase.

The cost is height. A stretch name can be 40 characters, so the title block is two lines tall on every screen, and an interval timer shows more empty space than it used to.

## What a running timer costs

The digits change once a second, so the run screen redraws once a second. `Session.zeroDate` is the instant elapsed time was zero, and the screen redraws on the whole seconds after it, which is exactly when a digit changes.

The ten audio checks a second do almost nothing. `RunModel` builds the schedule once per change, and `reconcile` returns before it allocates when the schedule, the engine, and the ducking state are all as it left them.

Speech never runs on the main thread. Looking up a voice waits on the system speech service, and on the main thread that froze the app for minutes on a cold simulator.

Measured on an iPhone 16 Pro Max simulator with iOS 27.2 and a Debug build, a running timer uses 3.0% of one core in a warm-up and 3.4% in a hold that counts reps. Each figure is the app's CPU time over 20 seconds, measured twice with the same result.

The clock digits cut from one second to the next. Rolling them with SwiftUI's `numericText` transition took the same warm-up to 71% of one core, and rolling only the rep count took the hold to 6.2%. Where that time goes was not profiled. The title, the captions, the buttons, and the chips do fade, because they change only when the run changes state.

## What is not proven yet

### Lowering and restoring other apps' music

Lowering other apps' music means adding `.duckOthers` to the audio session, and restoring it means removing the option while the session stays active. Apple documents a full deactivation as the way to restore other audio, and a full deactivation would stop the silent loop that keeps the app awake. Whether removing the option on a live session restores the music is something only a phone can show.

`CuePlayer.apply` is the only function that depends on the answer. Settings has a Troubleshooting screen with three strategies:

| Strategy | What it does | Cost |
| --- | --- | --- |
| Dip for each cue | Adds and removes `.duckOthers` on the live session | Unproven on a phone |
| Dip, then restart audio | Deactivates the session after each cue, then starts audio again | A short gap in the app's own audio after every cue |
| Low for the whole run | Keeps `.duckOthers` on from start to finish | Music is quieter for the whole workout |

Once one strategy passes the audio check in the README, delete the other two and the picker.

### Headphone presses

Exclusive mode rests on one assumption. It is that iOS makes this app the Now Playing app when all the app plays is a silent loop and short cues, and keeps it there while the run is paused and the phone is locked. No simulator can show that.

What is proven without a phone:

- What each command does to a run. The package tests cover it.
- That `RunModel` applies a command and offers Undo for a skip or a restart. The app tests cover it.
- That the lock-screen card carries the phase title, the caption, the workout name, the phase length, and the elapsed time. An app test reads the card back.

What only a phone can show:

- Whether the lock screen shows the card at all.
- Whether a press arrives while the run is paused and the phone is locked.
- Whether iOS reports the end of a call in a way that lets the run resume.

The Headphone check in Settings walks through the first two. `HeadphoneRemote` writes a line to the audio log for every command it receives, so a failed check shows whether the press arrived.

If silence does not make the app Now Playing, the fix is in one place: the silent buffer in `SoundBank` becomes noise far below hearing. If a paused run loses the lock screen, the fix is in `CuePlayer.standBy`.
