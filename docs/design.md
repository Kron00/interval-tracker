# About the design

## Why the timer never counts ticks

iOS suspends a backgrounded app within seconds, and timers that do fire can fire late. A timer that adds one second per tick falls behind every time that happens.

A `Session` stores one date instead: the moment at which elapsed time would be zero. Everything on the run screen is computed from `now` minus that date. Pause stores the elapsed time. Resume and skip move the date. "Finished" is not a stored state, so nothing has to notice the end and set a flag while the app is suspended.

`Session` lives in the `IntervalCore` package, which imports only Foundation. That is why its tests run on a Mac with no simulator.

## Why the cue schedule is data

`Session.cueSchedule` returns every sound of the run with the date it plays, grouped into `DuckWindow`s. A window is one stretch of lowered music and the sounds inside it. The package decides what sounds when and how long the music stays low. The app only executes the schedule.

For one phase change at time T:

| When | What |
| --- | --- |
| T − 3.5 s | Music dips |
| T − 3, T − 2, T − 1 s | Countdown beeps |
| T | Phase tone |
| T + 0.5 s | Voice, in a 1.5 s slot |
| T + 2.2 s | Music returns |

All of these numbers are in `CueTiming` in `Cues.swift`.

## How cues keep playing while the phone is locked

Three things have to hold.

- **The app stays awake.** The `audio` background mode keeps an app running only while its audio is running. `CuePlayer` loops a silent buffer for the whole run.
- **Beeps do not depend on timers.** `CuePlayer` queues every remaining sound on an `AVAudioPlayerNode` at an exact host time. The audio thread plays them. Voice phrases are rendered to buffers before the run starts, so a voice cue is queued the same way as a beep.
- **Recovery is one code path.** `RunModel` calls `CuePlayer.reconcile` ten times a second with the current schedule. `reconcile` compares the schedule with what it last queued and repairs any difference. A phone call, a route change, or a skip only marks the queued state as unknown, and the next call rebuilds it.

## What is not proven yet

Lowering other apps' music means adding `.duckOthers` to the audio session, and restoring it means removing the option while the session stays active. Apple documents a full deactivation as the way to restore other audio, and a full deactivation would stop the silent loop that keeps the app awake. Whether removing the option on a live session restores the music is something only a phone can show.

`CuePlayer.setDucked` is the only function that depends on the answer. Settings offers three strategies:

| Strategy | What it does | Cost |
| --- | --- | --- |
| Dip for each cue | Adds and removes `.duckOthers` on the live session | Unproven on a phone |
| Dip, then restart audio | Deactivates the session after each cue, then starts audio again | A short gap in the app's own audio after every cue |
| Low for the whole run | Keeps `.duckOthers` on from start to finish | Music is quieter for the whole workout |

Once one strategy passes the audio check in the README, delete the other two and the picker.
