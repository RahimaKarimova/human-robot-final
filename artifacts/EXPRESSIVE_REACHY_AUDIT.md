# Reachy simulation expressions

13 November 2026. Verified against the official Reachy Mini Control mock daemon and matching SDK **1.14.0**. The game sends real SDK antenna and head targets; the separate read-only viewer displays the official MuJoCo model using the daemon's measured motor state. No microphone or physical hardware was used.

## Behavior

- Gentle idle antenna sway and head turns; an attentive tilt while an optional question awaits a reply/skip.
- Greeting waves, small acknowledgement nods and a directional hint pose.
- Speech gestures continue for the entire fixed WAV, with antenna emphasis following its output loudness.
- Each gem celebration and treasure ending gets perked antenna cheers, small head bobs and a lift.
- Smooth transitions from the measured parked pose. Idle is gated by a recent game heartbeat and stops for pause, narration, outstanding jobs and stop. Connection failure disables idle locally.

## Evidence

- [Native expression checks](official-reachy/expressions.json): **ten checks passed**, including measured head/antenna movement, motion after three seconds of speech, real audio EOS, visible cheers, disabled idle, pause, resume and no late targets after cancellation. Idle excursion was 0.094 radians; late-speech excursion 0.293 radians; cheer peak 0.579 radians.
- [Complete adventure](official-reachy/expressive-campaign-verified.log): **66 assertions, zero failures**, with all chapters, fixed dialogue/hints, four gems and cave ending. Every scheduled line/hint required native completion; zero technical-failure output fallbacks.
- [Game controls and recovery](official-reachy/expressive-controls-verified.log): **33 assertions, zero failures**, including pause/resume, repeat without another joke exposure, skip, hint/narrator cancellation handoff, connection loss/recovery, real bookshelf reward and terminal stop. No technical-failure fallback occurred.
- Controller regression suite: **90 tests run, 88 passed and two optional live-Rasa checks skipped**. Covers continuous/distinct/bounded profiles, fixed-WAV rhythm, speed-limited transitions and idle suppression on pause, narration, stale game heartbeat, connection loss and terminal stop.
- [Official model render](official-reachy/expressive-robot-view.png): actual daemon joint positions applied to the official model; passive Stewart joints settle locally for display, with finite joint state. The viewer corrects the official model's antenna sign convention and reads head joints explicitly.

The game event schema and spoken scripts are unchanged. Fixed WAV analysis uses existing output assets only. The known restricted-environment Godot certificate-store warning remains unrelated to these offline/loopback assertions.

Larger antenna and head expressions are **simulation-only**. Physical Lite/Wireless adapters retain their small measured-baseline antenna profiles; head/body calibration and physical acceptance still require the robot. This test does not claim natural human-rated emotion, hardware stopping latency or physical speaker validation.
