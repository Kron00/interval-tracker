# About the design

## Why the timer never counts ticks

iOS suspends a backgrounded app within seconds, and timers that do fire can fire late. A timer that adds one second per tick falls behind every time that happens.

A `Session` stores one date instead: the moment at which elapsed time would be zero. Everything on the run screen is computed from `now` minus that date. Pause stores the elapsed time. Resume, skip, and restart move the date. "Finished" is not a stored state, so nothing has to notice the end and set a flag while the app is suspended. "Waiting" is not a stored state either. [How a routine waits for Start](#how-a-routine-waits-for-start) explains it.

`Session` lives in the `IntervalCore` package, which imports only Foundation. That is why its tests run on a Mac with no simulator.

## Why a stretch routine is not a second engine

A `Workout` has a name and a `Plan`. The plan is either `.intervals` or `.routine`. `Timeline` turns either plan into the same list of segments, and it is the only code that asks which kind of plan it has. `Session`, the cue schedule, the audio, and the run screen work on segments and never ask.

A routine becomes these segments:

| Stretch | Segments |
| --- | --- |
| Timed, done once | wait for Start, count-in, hold |
| Timed, done on each side | wait, count-in, hold left, wait, count-in, hold right |
| Counted in reps | one hold of no length for each side |

The count-in and the hold are ordinary segments with their own length, so the clock, skip, and the strip need nothing new for them. The count-in is 3 seconds unless the routine sets another length. A routine with no count-in has no count-in segments, and **Start** goes straight into the hold.

Daily Stretch has 10 stretches. One is counted in reps and 3 are done on each side, which makes 12 timed holds. Its 12 holds add up to 7:45 and its 12 count-ins to 0:36, so the app shows the total as "8:21 + reps". On the strip, a hold counted in reps is a marker of a fixed small width, so it is visible and takes nothing from the timed blocks. A wait for **Start** has no length and nothing to draw, so the strip leaves it out.

Each segment is one `Phase`. A phase knows its own title, caption, colour family, how-to link, and spoken words. The wait for **Start** also knows the length of the hold it leads into, which is what the clock shows before the countdown begins. The run screen reads those and draws them. It does not know which kind of workout it shows.

Three rules treat the wait and the count-in as part of the hold they lead into:

- Restart from a hold goes back to the start of its count-in, so you have time to get back into position.
- Next from a count-in ends the whole stretch, hold included. Next always means "the next stretch".
- "Up next" names what follows the hold, from the wait and from the count-in too.

## How a routine waits for Start

An interval timer moves on by itself. A stretch routine starts nothing by itself. Each timed hold begins when you tap **Start**, and each stretch counted in reps ends when you tap **Next**. A headphone press does the same.

`Timeline` marks the segments that hold the run. Such a segment is a gate. In a routine the gates are the waits for **Start** and the holds counted in reps. Every gate has no length. A count-in and a timed hold are not gates, and an interval timer has none.

`Session` adds one number to its date, the count of gates the run has passed. Elapsed time is still `now` minus the date, but it stops at the first gate that the run has not passed. A run whose elapsed time stands at that point is waiting. So waiting is derived from the date and the count, like "finished", and nothing has to set a flag when a hold runs out on a locked phone.

| Segment | What the run does |
| --- | --- |
| Wait for **Start** | Shows the stretch and the length of its hold, and waits |
| Count-in | Counts down by itself with a beep each second |
| Timed hold | Counts down by itself. At zero the run is at the next gate, or at the finish |
| Hold counted in reps | Shows the count and waits for **Next** |

**Start** adds one to the count and moves the date, so elapsed time carries on from the gate. The count-in and the hold then run by themselves. When the hold runs out, elapsed time reaches the next gate and stops there. No timer has to fire for that. The last timed hold has no gate after it, so the workout finishes by itself.

**Next** during a count-in or a hold leaves the count alone and moves the date to the end of the hold. The run is then at the next gate.

Restart leaves the count alone too. It moves the date back to the start of the count-in. A waiting run ignores restart, because a wait has nothing to restart.

The time you worked follows from the same numbers. It is the timed length, minus what you skipped, plus what you restarted, plus the time you spent in holds counted in reps. A wait for **Start** is not work, so `Session` drops that time when you tap **Start**. The clock keeps the time the run has been running even while the run waits, which is how a hold counted in reps knows how long you took.

## Why the cue schedule is data

`Session.cueSchedule` returns the sounds the run plays by itself, each with the date it plays, grouped into `DuckWindow`s. That is every sound up to the gate the run will wait at, or up to the finish. Nothing after a gate is scheduled until the run has passed it. A window is one stretch of lowered music and the sounds inside it. The package decides what sounds when and how long the music stays low. The app only executes the schedule.

`Session.vocabulary` lists every sound of the whole run. The app renders the voice phrases from that list before the run starts, so the name of the fifth stretch is ready long before the run reaches it.

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

Two limits follow from the slot:

- A stretch name is 40 characters at most. With ", right side" added, its slot is 3.6 s.
- In an interval timer, no countdown beep sounds before the voice has finished, and a phrase that cannot finish inside its phase is dropped.

A routine speaks a name only when a wait begins. A wait holds the run until you tap, so nothing can follow the phrase and no name is ever dropped. If you tap **Start** while the name is still playing, the count-in replaces it.

`SoundBank` renders each phrase to a buffer before the run and must deliver a buffer no longer than the slot. If the rendered speech runs long, `SoundBank` renders it once more at a faster rate. If the speech still runs long, `SoundBank` cuts it at the slot and writes a line to the audio log. In the simulator, all fourteen Daily Stretch phrases fit at normal speed. The closest is "Hip Flexor Couch Stretch, left side" at 2.48 s of 2.5 s. A phone may use a different voice, so that margin is not proven there.

### What a stretch boundary sounds like

The right side of Hip Flexor Couch Stretch runs out at T. Pigeon follows.

| When | What |
| --- | --- |
| T − 3.5 s | Music dips |
| T − 3, T − 2, T − 1 s | Countdown beeps |
| T | Phase tone. The screen shows PIGEON, "Left side", 0:45 and **Start**, and the run waits |
| T + 0.5 s | Voice: "Pigeon, left side" |
| T + 2.2 s | Music returns |

Nothing sounds during the wait. You tap **Start** at S.

| When | What |
| --- | --- |
| S | Music dips. First count-in beep. The screen shows "Get ready · Left side" and 0:03 |
| S + 1, S + 2 s | Count-in beeps |
| S + 3 s | Phase tone. The hold starts with no voice, because the wait already named it |
| S + 3.6 s | Music returns |

A count-in beeps once for each of its seconds, whatever the Countdown setting is, unless Countdown is off. The rule that keeps the first two seconds of a phase free of beeps does not apply to a count-in, because a count-in has no tone and no voice of its own.

The other side of a stretch is one more stretch as far as the sounds go. When the left side runs out, the tone sounds and the voice says "Pigeon, right side".

A hold counted in reps has two sounds, the tone that starts it and its name. It has no countdown, because it has no end to count down to.

The last timed hold ends on the finish tone, and "Workout complete" follows one second later. If the last stretch is counted in reps, they play when you tap **Next**.

## How cues keep playing while the phone is locked

Three things have to hold.

- **The app stays awake.** The `audio` background mode keeps an app running only while its audio is running. `CuePlayer` loops a silent buffer for as long as the run has a cue ahead of it.
- **Beeps do not depend on timers.** `CuePlayer` queues every remaining sound on an `AVAudioPlayerNode` at an exact host time. The audio thread plays them. Voice phrases are rendered to buffers before the run starts, so a voice cue is queued the same way as a beep.
- **Recovery is one code path.** `RunModel` calls `CuePlayer.reconcile` ten times a second with what the run needs: nothing, standby, or a schedule to play. `reconcile` compares that with what it last queued and repairs any difference. A route change or a skip only marks the queued state as unknown, and the next call rebuilds it.

Standby means the run is on but has nothing to play. A paused run is on standby. So is a waiting run, once the tone and the name that began the wait have sounded. Waiting has no audio code of its own.

## Why headphone controls need a second audio mode

iOS sends a headphone press to one app, the one it shows on the lock screen as Now Playing. An app whose audio mixes with other apps is never that app. So lowering your music under a cue and receiving a press cannot both happen in the same run.

`CuePlayer.sharing` holds the choice. The Headphone controls setting picks it.

| | Mixing | Exclusive |
| --- | --- | --- |
| Setting | Headphone controls off | Headphone controls on |
| Other apps' audio | Keeps playing and dips for each cue | Stops for the whole run |
| Headphone presses | Go to the music app | Come to this app |
| Paused, or waiting for **Start** or **Next** | Audio stops and the music is released | Audio is kept for 15 minutes |
| A call, or another app starts to play | Audio is rebuilt when it can be | The run pauses |

Mixing behaves as the app did before headphone controls existed.

Two parts of exclusive mode need a reason.

- **A run on standby keeps its audio.** With no audio, iOS suspends the app, and a suspended app cannot receive the press that would resume it or move it on. So the engine and the silent loop keep running while the run is paused or waiting, with no cue queued. After 15 minutes `CuePlayer` gives the audio up, so a forgotten workout does not hold it all day.

In mixing mode a waiting run releases the audio, so your music plays at full volume while you do your reps. If you lock the phone during a wait, iOS may suspend the app. That is acceptable, because without headphone controls **Start** and **Next** are on the screen and you unlock the phone to tap them.
- **An interruption pauses the run and the app does not take the audio back.** Mixing retries every second, which is harmless when audio mixes. In exclusive mode a retry would cut off the call, or stop the music you just started in another app. The run resumes when iOS reports that the interruption ended and playback should resume, or when you tap Resume.

`HeadphoneRemote` is the only file that imports MediaPlayer. It publishes the current phase to the lock screen and turns the five remote commands into `RunCommand` values. While the run waits, the lock screen reads "0:45 · Waiting for Start" or "10 reps · Waiting for Next" under the name of the stretch. `Session.perform` decides what each command does, so that part is tested on a Mac. `RunModel` only forwards the command and reconciles.

iOS reports a single press as play, pause, or a toggle of the two. A wait has nothing to pause. A press that paused a wait would also do harm, because **Start** keeps a paused run paused, and the count-in would begin paused. So while the run waits and is not paused, `Session.perform` treats those three commands as next, which is **Start** or **Next** on the screen. At every other time they pause and resume. A call can still pause a waiting run. A press then resumes the run, and the run goes back to its wait.

## Why nothing on the run screen moves

The phone sits on the floor and you read it at a glance. If the clock moved every time you paused, you would have to find it again.

So every block on the run screen has a fixed height and the clock takes the space that is left. A line with nothing to say still takes its line. The Undo and How to buttons appear inside a row that is always there. A state change swaps what is drawn inside a block, with a fade of a quarter of a second, and never changes where a block is. A UI test records where the title, the clock, the total, and two buttons are, and fails if any of them is somewhere else after a pause, a resume, a skip, a change of phase, a wait for **Start**, a count-in, or a hold.

A wait changes what six blocks draw:

| Block | While the clock counts | While the run waits |
| --- | --- | --- |
| Clock | The time left | The length of the hold, dimmed, or the rep count |
| Line under "Up next" | Empty | "Tap Start", or "Tap Next when done" |
| How to button | Hidden | Shown |
| Big white button | Pause | Start, or Next |
| Small back button | Restart | Dimmed, and does nothing |
| Small forward button | Next | Dimmed, and does nothing |

Before **Start**, the clock block shows the length of the hold. You see what you are about to start, and the digits are already the size and in the place they have when the countdown begins. They are dimmed, so a clock that has not started does not look like one that has stopped. The waiting screen takes the amber of the count-in and the hold takes green, so the two differ at a glance.

A countdown leaves no time for a video, so the How to button is hidden while the count-in or the hold counts. A wait and a pause show it. Nothing counts down in either, so opening a video costs no time and the app does not have to rewind anything. The button's place stays empty when the stretch has no link.

A wait has one thing to do. So the small back and forward buttons keep their places, go dim, and do nothing until the clock counts again.

The cost is height. A stretch name can be 40 characters, so the title block is two lines tall on every screen, and an interval timer shows more empty space than it used to.

## What a running timer costs

The digits change once a second, so the run screen redraws once a second. `Session.zeroDate` is the instant elapsed time was zero, and the screen redraws on the whole seconds after it, which is exactly when a digit changes. `Session.haltDate` is the instant the run next stops by itself, at a gate or at the finish. The screen is not redrawn after it, because a waiting run shows the same thing until you tap. A paused run is not redrawn either.

The ten audio checks a second do almost nothing. `RunModel` builds the schedule once per change, and `reconcile` returns before it allocates when the schedule, the engine, and the ducking state are all as it left them.

Speech never runs on the main thread. Looking up a voice waits on the system speech service, and on the main thread that froze the app for minutes on a cold simulator.

Measured on an iPhone 16 Pro Max simulator with iOS 27.2 and a Debug build:

| Run screen | Share of one core |
| --- | --- |
| Warm-up, counting | 3.1% and 3.2% |
| Timed hold, counting | 2.8% and 2.9% |
| Waiting for **Next** in a hold counted in reps | 1.8% and 1.9% |
| Waiting for **Start** | 1.7% and 1.8% |
| Paused | 1.6% and 1.7% |

Each figure is the app's CPU time over about 19 seconds, and each row shows two runs. A waiting run costs what a paused run costs. What is left is probably the ten audio checks a second, but that was not profiled.

The clock digits cut from one second to the next. In an earlier measurement, rolling them with SwiftUI's `numericText` transition took a warm-up from 3.0% to 71% of one core. Where that time goes was not profiled. The title, the captions, the buttons, and the chips do fade, because they change only when the run changes state.

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

Exclusive mode rests on one assumption. It is that iOS makes this app the Now Playing app when all the app plays is a silent loop and short cues, and keeps it there while the run is paused or waiting and the phone is locked. A stretch routine depends on that assumption before every stretch, because the press for **Start** or **Next** arrives during a wait. No simulator can show that.

What is proven without a phone:

- What each command does to a run. The package tests cover it.
- That `RunModel` applies a command and offers Undo for a skip or a restart. The app tests cover it.
- That the lock-screen card carries the phase title, the caption, the workout name, the phase length, and the elapsed time, and that it reads "Waiting for Start" or "Waiting for Next" during a wait. An app test reads the card back.
- That a waiting run asks the audio for standby once its tone and its name have sounded, and not before. An app test covers it.

What only a phone can show:

- Whether the lock screen shows the card at all.
- Whether a press arrives while the run is paused or waits for **Start** or **Next**, and the phone is locked.
- Whether iOS reports the end of a call in a way that lets the run resume.

The Headphone check in Settings walks through the first two. `HeadphoneRemote` writes a line to the audio log for every command it receives, so a failed check shows whether the press arrived.

If silence does not make the app Now Playing, the fix is in one place: the silent buffer in `SoundBank` becomes noise far below hearing. If a paused run loses the lock screen, the fix is in `CuePlayer.standBy`.
