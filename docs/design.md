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

### What the heads-up sounds like

In an interval timer, a warm-up or a rest that work follows can say that work is coming. With the default of 30 seconds, and the phase ending at T:

| When | What |
| --- | --- |
| T − 30.5 s | Music dips |
| T − 30 s | Voice: "Get ready. Thirty seconds." |
| T − 27.8 s | Music returns |
| T − 3.5 s | Music dips again for the countdown, as in the table above |

With 10 seconds the voice says "Get ready. Ten seconds." at T − 10 s and the music returns at T − 8 s. A 5-second countdown dips the music at T − 5.5 s, so the two never run together.

`Timeline.headsUp(in:_:)` is the one place that decides which phase gets a heads-up and when. It gives a phase one when all of these hold:

- The phase is a warm-up or a rest.
- The next phase is work. A rest before the cool-down or before the finish gets none.
- The phase is at least 15 seconds longer than the notice. Otherwise the heads-up would follow straight after "Rest".

`CueSchedule` asks that function where to put the voice. `Session.snapshot` asks it too, and reports `RunProgress.isHeadsUp` from that instant to the end of the phase. The caption on the run screen, the badge on the lock screen and the alert all follow from `isHeadsUp`, so none of them repeats the rule. A stretch routine has no warm-up, no rest and no work. The rule never matches there, and nothing has to ask which kind of plan it has. The count-in of a stretch also has the caption "Get ready". That is the count-in's own caption. `isHeadsUp` is false in a count-in, so the card shows no badge and does not alert.

The notice is `CuePreferences.headsUp`: off, 10 seconds or 30 seconds. The library file stores it as seconds. Versions from before the heads-up wrote no such value, so a file without it reads as 30 seconds.

`isHeadsUp` does not depend on the voice. With voice cues off the screen and the Live Activity still change, and nothing is spoken.

### How long a spoken phrase may be

An interval timer speaks a fixed set of phrases. A routine speaks the names its user typed. The schedule still has to know how long each phrase lasts, and it cannot ask the speech engine, because the package has none.

So the slot comes from the text alone. It is 0.4 s plus 0.06 s for each character, rounded up to a tenth of a second, and never below 1.5 s or above 4.0 s. Every phrase that names an interval phase is short enough to get 1.5 s, which is what it had before routines existed. "Get ready. Thirty seconds." gets 2.0 s, and in the simulator it takes 1.75 s. "Hip Flexor Couch Stretch, left side" gets 2.5 s.

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

## How the workout shows outside the app

A Live Activity is a view that iOS draws on the lock screen and in the Dynamic Island for an app that is not on screen. The view lives in an app extension, `IntervalTrackerWidgets`. The app hands iOS a value, and iOS draws the view from that value when it likes, also while the app is suspended.

`Shared/RunActivity.swift` is compiled into both the app and the extension. It holds that value, `RunActivityAttributes.ContentState`, and the colours of the phases. The value is plain: a title, a caption, what is up next, a colour key, what stands in the clock's place, and whether the heads-up is on. The extension does not import `IntervalCore` and decides nothing about a run.

### Why a run sends so few updates

The clock's place is one of four cases.

| Case | What it carries | Who moves it |
| --- | --- | --- |
| Counting | The two dates the phase runs between | iOS. `Text(timerInterval:)` and `ProgressView(timerInterval:)` tick by themselves |
| Paused | The time left, as text | Nothing |
| Waiting | The length of the hold and that the run waits for **Start**, or the rep count and that it waits for **Next** | Nothing |
| Finished | The time worked | Nothing |

So the value is the same at every instant inside one phase. The two dates come from `Session.phaseEnd(at:)`, which adds the end of the segment to the session's one date. It never uses `now`, so two calls in the same phase return the same date to the last bit.

`RunModel` calls `LiveActivityController.reconcile` ten times a second, next to the audio. `reconcile` builds the value, compares it with the last one, and returns when they are equal. A run sends one update for each change of phase, pause, resume, wait, heads-up and finish. Norwegian 4x4 sends 14 in 38 minutes: 9 changes of phase, 4 heads-ups and the finish. A timed stretch sends three: its wait for **Start**, its count-in and its hold.

A wait carries which tap it waits for as a key, `start` or `next`, the way the colour is a key. The extension turns the key into a button with that word and its symbol. A run that is paused at a wait shows what the wait shows in the clock's place, the length of the hold or the rep count, and not an empty clock.

### How a tap on the card reaches the run

A waiting run has a button on the card, **Start** or **Next**, where the other states have a badge. The row that holds the badge or the button has the height of the button in every state, so the card is equally tall with either.

The button runs `AdvanceRunIntent`, a `LiveActivityIntent`. `Shared/RunActivity.swift` holds the intent, so the extension can draw the button. iOS runs `perform` in the app's process, also when the phone is locked, and it starts the app in the background if it has to. The app points the intent at its one `RunModel` when it launches. The extension has no run, and its copy of the intent never runs.

A tap arrives some time after iOS drew the card. By then the run may have moved on, and a second tap may follow the first. So a waiting card carries one more plain value, a number that `RunModel` replaces with every change to the run, and the button hands that number back. `RunModel.advance(fromWait:)` does nothing unless the number is still the newest and the run waits and is not paused. A tap that comes late or comes twice therefore changes nothing. It cannot pause or skip a hold that is counting, and a second tap on **Next** cannot also start the stretch that follows. The number is not the place in the workout, because **Undo** comes back to the same place and so does the next workout: a tap that **Undo** overtook would press again, and a tap for one workout would move the next.

A tap that passes this check is a headphone press. `RunModel.handle` gets the play command, `Session.perform` reads it as **Start** or **Next** because the run waits, and **Undo** is offered as for any press. The extension still decides nothing about a run.

`advance(fromWait:)` returns only when the card shows the change. iOS may suspend the app as soon as the intent returns, and an update that was still on its way would be lost.

The intent is also an `AudioPlaybackIntent`, because **Start** leads into a count-in that beeps. In mixing mode a waiting run has released the audio, so the tap may reach an app that iOS has suspended, and the app then has to start its audio from the background. [The Live Activity on a phone](#the-live-activity-on-a-phone) says what is unproven about that.

The button needs no entitlement, no app group and no `UsageDescription` key.

### Why one task talks to ActivityKit

`Activity.update` and `Activity.end` are async. Two updates started on two ticks could land in either order. So `reconcile` only records the card that is wanted and makes sure one task is running. The task takes the newest wanted card, shows it, and looks again. A change that arrives during an update is shown next. A change that was replaced before its turn is skipped.

`SystemActivityDisplay` is the only code that calls ActivityKit. The controller reaches it through the `RunActivityDisplay` protocol, and the app tests put a recorder in its place to check the order.

### When the activity starts and ends

| The run | The activity |
| --- | --- |
| Starts | Requested. iOS allows a request only while the app is in front, and Start is a tap in the app |
| Changes phase or state | Updated |
| Reaches its heads-up | Updated with an alert, which lights a locked screen and opens the Dynamic Island. The alert carries a silent sound file, because the system's alert sound would play over the voice and an alert cannot have no sound. It alerts once for each run through the phase, so a skip and its Undo do not alert again |
| Finishes | Updated, then ended, and left on the lock screen for two minutes |
| Is ended, or **Done** is tapped | Removed at once |
| Is brought back by Undo after the finish | Requested again, because an ended activity takes no updates |

A session is not saved, so a crash or a force quit leaves an activity that counts down to a run that no longer exists. Every launch removes all activities of the app before it does anything else.

Nothing else in the app depends on the activity. If Live Activities are turned off, or iOS refuses the request, the controller writes one line to the log, Settings shows the reason, and the next change of phase tries again. That is also what happens if the extension is missing from the installed app.

A paused run, and in mixing mode a waiting run, release the audio, so iOS may suspend the app. The card is right anyway, because those states do not change with time.

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

In mixing mode a waiting run releases the audio, so your music plays at full volume while you do your reps. If you lock the phone during a wait, iOS may suspend the app. That is acceptable, because without headphone controls **Start** and **Next** are on the screen and on the card of the Live Activity, and iOS wakes the app for a tap on the card.
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

The question that the X asks is drawn over the run screen and moves nothing under it. Its line about the history has room for two lines of text whichever sentence it shows.

The cost is height. A stretch name can be 40 characters, so the title block is two lines tall on every screen, and an interval timer shows more empty space than it used to.

The heads-up uses the caption line, which is always there. During it the line reads "Get ready" in place of the round. In a warm-up the line is empty until then.

## How a description becomes a workout

**Describe a workout** sends the text you type to OpenAI's Responses API and gets back JSON. A language model can return anything, so its answer is treated like a file from an unknown version of the app. It is decoded, checked, and only then becomes a `Workout`.

`WorkoutBlueprint` in the package is that JSON, decoded and not yet checked. `WorkoutBlueprint.workout()` is the only code that knows how an answer maps to a workout. It builds the workout through the same failable initialisers that the editor and the library file use, so a generated workout cannot hold a value that a hand-built one could not.

| In the answer | What `workout()` does |
| --- | --- |
| A number above a limit, such as 500 rounds | Uses the limit |
| A warm-up, rest, or cool-down of zero or less | Leaves the phase out |
| A stretch name longer than 40 characters | Cuts it to 40 |
| More than 99 stretches | Keeps the first 99 |
| A stretch with both a hold and reps | Counts it in reps |
| No name, no work time, no rounds, no stretches, or a stretch with no name or no amount | Fails with a `BlueprintError` that names what was wrong |

The model never chooses the count-in of a routine. A generated routine gets the count-in that a new routine has in the editor. A stretch waits for Start, so the model has no pause to plan, and the instructions tell it not to add get-ready steps as stretches.

The JSON Schema of the answer and the instructions for the model are constants next to `workout()`. The instructions state the same limits that `workout()` enforces, with the numbers taken from the package. A change to the workout model is then a change to one file.

The schema is in the strict form that OpenAI's structured output takes. Every property is required, an absent value is null, and no other property is allowed. OpenAI does not say whether a request that a ChatGPT plan pays for may carry a schema. If the server refuses the schema, `WorkoutGenerator` sends the request once more with the schema written into the instructions. `workout()` checks the answer in both cases, so the app does not depend on the server holding the model to the schema.

An interval timer has one work length and one rest length. A pyramid cannot be stored. The instructions tell the model to choose one length and to say so in `note`, and the result screen shows the note above the total. The three examples on the sheet are descriptions that a workout can hold in full.

### What the sheet keeps while it asks again

An answer costs a request, so the sheet does not give one up until it has a better one. `DescribeState` is the whole state of the sheet, and two of its cases carry the answer that the user already has.

| The sheet | What it holds |
| --- | --- |
| Asks for the first answer | Nothing |
| Asks again after **Try again** | The answer on the screen when **Try again** was tapped |
| Shows an answer | The answer, and the failure of the last retry if that retry failed |

`DescribeState.ended(with:)` and `DescribeState.cancelled` are the only places that decide where the sheet goes next. A retry that succeeds shows the new answer. A retry that fails, or that the user cancels, shows the earlier answer again, with the failure above it if there was one.

**Edit** opens the editor as a sheet over the result, so **Cancel** in the editor leaves the result as it was. **Save**, on the result or in that editor, closes the sheet and opens the detail screen of the saved workout. The new card is the last one in the library and can be below the edge of the screen, and the detail screen is where **Start** is.

## How the app signs in to ChatGPT

The app uses OpenAI's "Sign in with ChatGPT" flow for open-source apps. It is OAuth with PKCE and a public client. No secret is involved, so there is none in this repository. The request for a workout then goes to `POST https://api.openai.com/v1/responses` with the token from the sign-in, and OpenAI counts it against the user's plan.

The app does not use the Codex CLI's client id or the `chatgpt.com/backend-api` route. OpenAI's documentation tells other apps not to.

### Why the app runs a listener on 127.0.0.1

OpenAI ends a sign-in by sending the browser to `http://127.0.0.1:<port>/auth/callback`. It accepts no other kind of redirect address, and it has no device-code flow. The system sign-in sheet, `ASWebAuthenticationSession`, tells an app only about a redirect to a custom scheme or to an HTTPS address. So the sheet cannot hand the app the answer.

`LoopbackCallback` fills the gap. Before the sheet opens, the app starts a small HTTP listener on 127.0.0.1, on a port that the system chooses, and puts that port in the redirect address. When ChatGPT sends the browser there, the listener hands the request to the app and answers with a redirect to `intervals-auth://done`. The sheet watches for that scheme and closes.

The listener is bound to the loopback address, so no other device can reach it. A hosted test proves that the listener's port is still free on the machine's network address. The listener stops when the sign-in succeeds, when the user cancels, and after ten minutes.

`NWParameters.acceptLocalOnly` is not set. With it, the simulator reset every connection before the listener saw a request.

### Why there is a second route through Safari

The sheet was built before anyone had seen it reach the listener on a real iPhone. So Settings also offers **Sign in with Safari**, which does not depend on it. The sheet has since worked on a phone, and the Safari route has not been tried on one. [Building workouts with ChatGPT](#building-workouts-with-chatgpt) has the details.

Safari is a separate app. While the user signs in there, Intervals is in the background, and iOS may suspend it. Two things can then happen when ChatGPT sends Safari to the redirect address.

| Intervals is | Safari shows | The user |
| --- | --- | --- |
| Still running | The listener's page: "Signed in. Go back to Intervals." | Goes back to the app |
| Suspended | An error, with the redirect address in the address bar | Copies the address and pastes it into the app |

A pasted address and a request to the listener are read by the same function, `SignInAttempt.grant(from:)`. It checks the `state` value against the attempt in progress, so an address from another attempt is turned away.

### What is stored, and where

Everything about the account is one value, `Vault`, kept as one Keychain item: an id for this install, the client id that OpenAI issued, the tokens, and the API key. Nothing about the account is in `UserDefaults` or in a file. No token, code, or key is written to a log.

What the screens show is derived from the vault and never stored beside it.

| The vault holds | The account is |
| --- | --- |
| No tokens and no key | Signed out |
| No tokens and a key | Key only |
| Tokens whose scope has `chatgpt.tokens.use.direct` | Signed in, and the plan pays |
| Tokens without that scope | Signed in without plan usage. The key pays if there is one. |

A valid sign-in does not by itself allow plan usage. Only the scope that came back with the tokens does.

`ChatGPTAccount` is an actor, so the Keychain and the token responses are never handled on the main thread. `WorkoutGenerator` is an actor for the same reason: it reads the stream and builds the workout away from the main thread. `ChatGPTModel` is the main-actor object that the screens observe.

### Why refreshes wait for each other

An access token lasts one hour. A refresh returns a new access token and a new refresh token, and the old refresh token stops working. Two refreshes at the same time would leave one caller with a dead token, and OpenAI treats a reused refresh token as a reason to end the session.

So `ChatGPTAccount` keeps the refresh in progress, and every caller that needs a token waits for that one request. A token within two minutes of its end is refreshed before use.

| The refresh | What the app does |
| --- | --- |
| Succeeds | Stores the new tokens |
| Is refused with `invalid_grant`, `refresh_token_expired`, `refresh_token_reused`, or `refresh_token_invalidated` | Deletes the tokens, keeps the client id, and asks the user to sign in again |
| Fails for any other reason, such as no connection | Keeps the tokens and reports that OpenAI could not be reached |

**Sign out** deletes the tokens and the client id first, then tells OpenAI to revoke the refresh token. The client id belongs to one ChatGPT user, and the next person to sign in may be someone else. The id for the install stays.

The app checks the `nonce` in the ID token against the sign-in attempt. It does not check the token's signature. The token comes straight from OpenAI's token endpoint over TLS, and OpenID Connect accepts that in place of the signature check.

## How the app reads heart rate

The owner wears a Google Fitbit Air, a band with no screen. In the Google Health app, under Connections, Fitbit Air, Share heart rate, it broadcasts live heart rate over Bluetooth Low Energy so that gym equipment can read it. An open-source reader gets it through the Bluetooth SIG's standard Heart Rate Service: service `0x180D`, characteristic `0x2A37`, a notification about once a second. Nobody has read it from this app yet.

So the app is a client of that standard service and of nothing made for one band. Any chest strap or armband that sends heart rate over Bluetooth (Polar, Wahoo, Garmin HRM) works the same way, and a change on Google's side can at worst stop the Air, not the feature.

`HeartRateMeasurement` reads the characteristic. Bit 0 of the first byte says whether the heart rate that follows is one byte or two, least significant first. The energy expended and the RR intervals that can come after it are not read. A value of 0, which a strap sends without skin contact, and anything else outside 25 to 250 is not a heart rate and is dropped when it becomes a `HeartRateReading`.

### Bluetooth stays in one file

`BluetoothHeartRateSource` is the only file that imports CoreBluetooth, the way `LiveActivityController.swift` is the only one that imports ActivityKit. Every call and callback runs on one serial queue, so nothing waits on Bluetooth on the main thread. Events reach the main thread in order.

The rest of the app tells the source what it wants, a `HeartRateDemand`: whether to scan, and which monitor to stay connected to. The source makes that so and keeps it so. `HeartRateMonitor` derives the demand. It names the remembered monitor while a run is on or Settings is open, and nothing otherwise, so the radio is idle between workouts.

| The source | What the app shows |
| --- | --- |
| Has no demand that needs Bluetooth | Nothing. It has not even made its `CBCentralManager` |
| Scans, or looks for a remembered monitor that iOS no longer knows | Searching, and a dash with "Connecting" |
| Has asked iOS to connect | Connecting. iOS keeps a connect pending until the monitor is in range, so the run keeps trying without a timer |
| Has subscribed to the measurement | Connected, and the number |
| Lost the link | "No signal", and it connects again at once |
| Was refused the measurement | "No signal", and Settings says to tap Pair if iOS asks, or to pick the monitor again |

Making a `CBCentralManager` is what shows the permission prompt, so the source makes one only for a demand that needs Bluetooth. That happens first when the user opens **Find a monitor**. A run or Settings asks for Bluetooth only once a monitor is remembered, and a monitor is remembered only from **Find a monitor**. So the app never asks at launch, and the prompt never appears over a workout as it starts. The source also turns off iOS's own alert that Bluetooth is off, for the same reason. Settings says so instead.

The Air may need pairing before it streams. iOS asks when the app subscribes to a characteristic that needs it. If the user declines, the subscription fails and the source stops asking. Asking again in the middle of a workout would put the prompt back on the screen with every reconnect. Picking the monitor again in **Find a monitor**, or the next run, asks again.

No test touches Bluetooth. The app tests pass a source that records the demands and sends the events a test writes. UI tests launch with `-hrStub new` or `-hrStub remembered` and get `StubHeartRateSource`. A scan finds one monitor, and once connected it sends one reading a second, from 100 up to 187 and back in a minute, so half a minute passes through every zone of the standard maximum.

### The zones

Five zones, each from a share of the maximum heart rate: zone 1 from 50%, zone 2 from 60%, zone 3 from 70%, zone 4 from 80% and zone 5 from 90%. Below 50% is below zone 1. `MaxHeartRate.zone(of:)` in the package is the rule, and the run screen, the card and History all ask it. It compares in whole numbers, `bpm × 100 ≥ percent × max`, so 60% of 190 is 114 exactly and 114 is in zone 2.

The maximum is a setting from 120 to 220, 190 until the user changes it. Settings suggests 220 minus your age. A record keeps the maximum its zones were worked out with, so changing the setting does not change a past run.

The zone colours run cool to hot: silver below zone 1, then sky blue, lime, yellow, orange and pink. A zone is drawn on top of a phase, whose fill already has a colour. So no zone colour is a phase colour, and each sits on a dark backing.

### What the run screen shows

The readout has its own slot, above the total in portrait and under the clock in landscape. The slot is there in every state of the run, so a pause or a wait moves nothing. `testNothingMovesWhenTheRunChangesState` runs with the stand-in remembered and measures the slot too. With no monitor remembered, the slot is not there at all, and the screen is as it was before heart rate.

A number shows only while the link is up and the latest reading is at most 5 seconds old. Otherwise the slot shows a dash and "Connecting" or "No signal". A stale number is never shown as if it were live.

The readout observes `HeartRateMonitor` by itself, through `LiveHeartRate`. A reading redraws the readout and nothing else, and a `TimelineView` redraws it once more when the reading goes stale. The run screen's own body never reads the reading, so it still redraws once a second while counting and not at all while paused or waiting.

### Why the card waits for heart rate

Everywhere else the card is the same for a whole phase, and iOS ticks the countdown. Heart rate is the one field that changes inside a phase. Sending it every second would mean an update a second for the whole workout, and iOS limits how often an app may update a Live Activity.

So `LiveActivityController.reconcile` holds back a change of the heart rate alone until 5 seconds after the last card it sent. A change of zone goes out at once, and so does a reading that goes to a dash or comes back from one. Any other change, of phase or state, goes out at once as before and carries the heart rate of that moment. The card is at most 5 seconds behind the run screen within a zone, and its colour is never behind.

### What History keeps

`RunModel` keeps every reading while the run is active and not paused. A paused run keeps none, and neither does a run that has finished. When it reports the run, it hands the readings to `HeartRateSummary` with the max heart rate of the moment. A run with no reading has no summary, and its entry looks as entries did before.

| The summary | How it is worked out |
| --- | --- |
| Average | The mean of the readings, rounded |
| Maximum | The highest reading |
| Time in each zone | From each reading to the next, in the zone of the first. A gap of more than 10 seconds counts for nothing, so a pause or a lost signal is not time in a zone. The last reading adds nothing |
| Graph | One point for each 5 seconds after the start that had a reading, the mean of its readings. A gap in the readings is a gap in the line |

The record carries the summary under an optional `heartRate` key. Files that versions before 1.4 wrote have no such key and load as before. A summary that is not valid, such as a heart rate outside 25 to 250, a maximum below the average, or a time in a zone that is no length, refuses the file like any damaged record, and the store sets the file aside. The file version stays 1. A new version would make an older app set aside a file it can still read: an older app ignores the key it does not know, and loses only the heart rate if it writes the file again.

A point of the graph is written as a pair of numbers, `[second, bpm]`. An hour has 720 points, and with named keys the history file would grow several times over.

Nothing goes to Apple Health or to Google. The summary lives in `history.json` only.

### What only a phone can show

- Whether the Fitbit Air streams to this app at all. The research is one open-source reader and one app listing, and one review says a bike computer could not read it.
- Whether the Air asks to pair, and whether the app recovers when the prompt is declined.
- Whether Share heart rate turns itself off after a while.
- Whether readings keep arriving with the screen locked. The app has the `bluetooth-central` background mode, and a run's audio keeps it awake, but neither has been seen with a monitor.

Settings shows the remembered monitor's live reading, so the owner can check the first two in ten seconds.

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

The Live Activity was measured against the commit before it, on the same simulator with a Debug build. Each figure is the app's CPU time over 19 seconds of a Norwegian 4x4 warm-up, as the median and the range of five runs. The two builds took turns.

| | Before | With the Live Activity |
| --- | --- | --- |
| Run screen in front | 3.0% (2.8% to 3.7%) | 3.0% (2.4% to 3.5%) |
| Behind the home screen, with the Dynamic Island showing | 2.5% (2.2% to 2.7%) | 1.6% (1.6% to 1.6%) |

In front the two builds do not differ. The Mac ran other work during these runs, which is the likely reason for the spread. Behind the home screen the new build used less in all five pairs. A 10-second `sample` of each build puts the difference on the main thread, in SwiftUI's render of the run screen: 37 samples before and 13 after. Why SwiftUI does less there was not found.

In a stretch routine the Live Activity was checked with a 15-second `sample` of a waiting run, with the run screen in front. `LiveActivityController.reconcile` took 2 of 5,843 main-thread samples while the run waited for **Next**, and 10 of 11,005 while it waited for **Start**. Three alternating runs of each build were also timed in those states, but the Mac was running other work and the runs of one build differed by more than the two builds did, so they show nothing.

The history needs one more check on each of the ten ticks a second, a snapshot that says whether the workout has finished. Five runs of a counting warm-up with the check and five without, taken in turn over 30 seconds each, gave a median of 2.8% and 2.6% of one core. The ranges were 2.4% to 3.5% with the check and 2.5% to 4.7% without, on a Mac that was busy with other work, so the check has no cost that this measurement can show.

The question that the X asks redraws one line once a second while it is open. Three runs of this build and three of the commit before it were timed in turn over 22 seconds each, in the warm-up of 20/20 HIIT, first with the clock counting and then with the question open. A UI test started the workout and then slept.

| | Before | With the line |
| --- | --- | --- |
| Warm-up, counting | 5.7%, 6.2% and 11.6% | 3.0%, 8.2% and 8.9% |
| The question open | 3.6%, 9.6% and 10.7% | 2.0%, 2.7% and 9.6% |

The Mac was busy with other work, and the runs of one build differ by more than the two builds do. So these figures show no cost of the line, and they are too rough to rule a small one out.

The clock digits cut from one second to the next. In an earlier measurement, rolling them with SwiftUI's `numericText` transition took a warm-up from 3.0% to 71% of one core. Where that time goes was not profiled. The title, the captions, the buttons, and the chips do fade, because they change only when the run changes state.

## Why the history has its own file

The library file holds the workouts you built. The history holds one `WorkoutRecord` for each run. They are two files, `library.json` and `history.json`. Each has its own version number and its own store. `LibraryStore` is the only writer of the first file, and `HistoryStore` is the only writer of the second.

A store that cannot read its file moves the file aside and starts empty. If the history were part of the library file, one damaged history entry would take every saved workout with it. With two files, a bad history file costs the history and nothing else. The app writes the history after every run and writes the library only when you edit a workout, so the file that changes most is the one that can be lost.

A record keeps the id of its workout and a copy of the name and the kind. The History screen shows the copy, so an entry reads the same after you rename or delete the workout. The id has one use. **Start again** looks the workout up in the library by it, and the button is absent when the workout is gone.

`History` in the package decides what the history keeps. It keeps every completed run, a run ended early only after 60 seconds of work, and no more than the newest 1000 entries. `HistoryStore` adds one rule that the package cannot know. It drops the audio check, because that run tests the phone and is not a workout.

Grouping by day and the summary of the week take a `Calendar`, and no code in the package asks for the current date. So the package tests choose the time zone and the first day of the week, and the app passes the calendar of the phone.

## When a run goes into the history

`RunModel` reports every run one time, as a `WorkoutRecord`, to `onRunOver`. A run is reported at the first of two moments:

- You leave the run screen. That is **Done** on the finish screen, or **End workout** after the X. A new run that starts over a run in progress leaves that run too.
- A tick finds the workout finished and no Undo on offer.

The second moment is for a workout that finishes by itself while the phone is locked. Without it, the run would be recorded only when you come back and tap **Done**.

Undo is the reason the second moment waits. A skip of the last phase finishes the workout, and for 6 seconds **Undo** can bring the run back. If the skip recorded the run, Undo would have to delete the entry from the file again. Nothing is recorded while Undo is on offer, so Undo never has an entry to delete.

`RunModel` keeps the start date of the run that it has not reported, and sets the date to nil when it reports. That one optional is the start time of the record and also says whether the run was reported. **Done** after a finish that a tick already reported finds nil and reports nothing.

Only the tick checks for a finished workout. The `reconcile` that follows a change must not, because of an order inside `RunModel`. `change` clears `undo` before it applies a skip, and the skip offers Undo again only after `change` returns. A check in between would find a finished workout with no Undo, and it would report a run that Undo can still bring back.

A run that ends part way is recorded with `Session.worked(at:)`. That is the arithmetic of the finish screen, taken at the moment you end the run. It counts the time you have spent so far in a stretch counted in reps, and it does not count a wait for **Start**.

The question "End this workout?" says what the history will do, because a run of under a minute used to vanish without a word. `History.keeps(_:worked:)` is the rule. `History.add` asks it about a record, and the dialog asks it about the run as it stands. The audio check is never recorded, so its dialog has no such line. `HistoryStore.records(_:)` is that rule, for the store and for the dialog.

The answer can change while the dialog is open, when the work reaches a minute. A run that waits in a stretch counted in reps is working, and its screen is not redrawn. So the line in the dialog is redrawn once a second by itself, for as long as the dialog is open.

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

### The Live Activity on a phone

The UI tests lock the simulator and read the card from the lock screen. They show that the card starts with the run, says to get ready, follows the run into work, shows the finish, comes back with Undo, and goes away with the run. In a routine they show that the card waits for **Next** with the rep count, and waits for **Start** with the length of the hold, which does not count down. They tap **Next** on the lock screen and **Start** in the opened Dynamic Island, and see the routine move on each time. They also show that a launch removes the card of a run that was force quit. Screenshots show the Dynamic Island in its compact and expanded forms, and that the alert opens it.

No UI test asserts on the count-in or the hold of a stretch on the lock screen. Both end by themselves, and a slow machine could miss them. The app tests cover what the card carries in those two phases, and two screenshots taken two seconds apart show the hold counting down on the lock screen.

What only a phone can show:

- Whether the alert lights the screen of a locked phone, and whether it stays silent. The simulator plays no alert sound either way.
- Whether the card keeps up for a whole workout on a locked phone. The app updates it from the background, so this rests on the same thing as the cues: the audio keeps the app awake.
- Whether AltStore installs the extension. AltStore signs the app again with the owner's Apple Account and may ask whether to keep app extensions. If the extension is removed, the app is expected to run with no card, but that path has never run.
- What the minimal form of the Dynamic Island looks like. iOS shows it only when two apps have an activity.
- Whether a tap on **Start** or **Next** reaches the app on a locked phone, and whether iOS asks for Face ID or the passcode first. The simulator has no passcode.
- How long a tap takes. In the simulator iOS handed the app two taps on a locked screen 3.3 and 2.2 seconds after they were made, on a Mac that was busy with other work. The app then changed the run and sent the new card within 0.05 seconds. So the wait is before the app runs, and nothing in the app can shorten it.
- Whether the count-in sounds after **Start** on the card when headphone controls are off. The app may be suspended by then, and it has to start its audio from the background. `AdvanceRunIntent` is an `AudioPlaybackIntent` for that reason. If the audio does not start, the card still counts the hold down, and the run screen shows **No sound** when you open the app.

The audio check in Settings uses 10 seconds of notice, so it shows the first two in one minute on a phone.

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

### Building workouts with ChatGPT

One test contacts OpenAI, `LiveOpenAITests`, and it is skipped unless `TEST_RUNNER_LIVE_OPENAI=1` is set, because a person has to sign in. The protocol comes from OpenAI's documentation and from three open-source clients that implement it.

What is proven without an account:

- What the app sends. Hosted tests read the sign-in address, the code exchange, the refresh, the revocation, and the request for a workout, and compare each with the documented fields.
- What the app does with each documented answer: the tokens, a scope without plan usage, each refresh failure, each error code, a stream that ends early, and a refused schema.
- That the system sign-in sheet reaches the listener on the simulator. A UI test signs in through the real sheet and the real listener. Only ChatGPT's page and the token endpoint are stand-ins.
- That a signed simulator build stores the vault in the Keychain and reads it back. An unsigned build has no Keychain, so CI skips those two tests.

What one account showed. `LiveOpenAITests` ran against OpenAI on 12 November 2026 in the simulator. It drives `ChatGPTModel` with the real transport, the real listener, and a vault in memory. It prints the sign-in address, and the address is opened in a browser on the Mac, whose loopback interface the simulator shares. `Scripts/chatgpt-probe.py` sends the same requests without the app and ran the same day:

- OpenAI registered a client it had never seen and issued it an `oaiapp_` identifier. It granted all six scopes, with a one-hour access token.
- The plan may be used by other apps, and a plan request may carry a strict JSON Schema with `store: false` and `stream: true`. The fallback that writes the schema into the instructions was not needed.
- The plan listed `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6.1-terra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra` and `gpt-5.6-luna`. `ModelList.smallest` picks `gpt-6-luna` from that list, and a test pins it.
- The app turned the plan's answer to "15-minute hip mobility routine" into a routine of eight stretches through `WorkoutBlueprint`.
- Revoking the refresh token succeeded.

What a phone showed. On 13 November 2026 the owner used the app on an iPhone, installed from AltStore:

- **Sign in with ChatGPT** opened the system sheet, and the sheet reached the listener on 127.0.0.1. A phone does not share a Mac's loopback interface, so this is the first proof of the listener outside the simulator.
- The app built a workout from a description.
- The app was still signed in after it was closed and opened again. So a build that AltStore signed stores the vault in the Keychain and reads it back.

What only an account can still show:

- Whether another plan may be used by other apps. The probe checked one.
- Whether the smallest model is found when OpenAI renames its models. The model list does not say which model is the smallest, so `ModelList.smallest` goes by the names "luna", "nano", and "mini", and otherwise takes the first model listed.

What a phone has still to show:

- Whether **Sign in with Safari** works there, with or without the pasted address.
- Whether a token refresh works there. Nobody has watched one on a phone.
