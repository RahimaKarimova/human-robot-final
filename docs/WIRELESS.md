# Wireless output worker

This implements the **on-robot** Wireless output route. The robot was unavailable; physical audio, network connectivity and gestures have **not** been verified. Unit tests cover protocol behavior and explicit ALSA sink selection. The controller/simulator tests cover the common chapter flow. The native SDK/device path still needs a real robot bench test.

The worker runs on Reachy's Linux computer, connects to its existing localhost daemon with the optional SDK, and plays fixed WAVs directly through the configured **`reachymini_audio_sink`** ALSA output. It reuses the same GStreamer EOS, pause/cancel and small optional antenna profiles as Lite. It never sends audio to the laptop's default speaker, opens a WebRTC camera/microphone stream or treats a successful HTTP upload as proof of spoken completion.

The official [quickstart](https://huggingface.co/docs/reachy_mini/en/SDK/quickstart) documents SSH access as `pollen@reachy-mini.local`; use the actual account/address for your robot. The official [Wireless troubleshooting guide](https://huggingface.co/docs/reachy_mini/v1.8.4/troubleshooting) describes its `reachymini_audio_sink` speaker alias. The adapter targets SDK **1.12.0**, as reviewed in pinned upstream source; confirm the daemon version first and reconcile mismatches before using it. No robot firmware or SDK was changed during this task.

## Prepared package

`build/EchoIsland-Wireless-Agent.zip` contains only the worker's Python source, fixed companion scripts/WAVs, the game catalogue/manifest and credits. It excludes session capabilities, recordings, speech models, caches, tools and installed environments. Rebuild after changing scripts/voices:

```powershell
services/controller/.venv/Scripts/python.exe dev/build_wireless_bundle.py
```

It is an agent package, not the playable game ZIP. Copy it to your own robot and extract it into your chosen project folder. Python 3.11+ and the matching Reachy SDK with working system GStreamer/PyGObject are required on that Linux host. Use the robot's documented Python environment or a separate environment that can import its GStreamer bindings. The worker's `no_media` SDK connection temporarily releases the daemon's media devices for direct output; SDK cleanup restores daemon ownership. It does not enable motors, start recording or physically disable the microphone.

## Connection steps when the robot arrives

1. On the PC, run `Play-Controller.ps1 -Wireless -Condition control`. Leave the launcher running at the title screen. It prints the path to a fresh **`.robot.json`** capability file. No SSH connection or remote installation is performed automatically.
2. Establish a reverse SSH tunnel so the worker can reach the PC's loopback-only controller. For the default port, run this in a separate terminal:

```text
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=2 -o ServerAliveCountMax=2 -R 127.0.0.1:8765:127.0.0.1:8765 pollen@reachy-mini.local
```

Use your actual account/address. If the launcher uses another port, substitute it consistently in the tunnel and config. The controller remains bound to loopback; no firewall/public API configuration is needed.

3. Copy **only that fresh robot capability file** to the robot using SCP/SFTP, along with the prepared package. Keep it out of Git, shared ZIPs and screenshots. The game capability and experimental condition are not required by the worker. On the robot, protect the copied capability file with `chmod 600`.
4. In a second SSH terminal, open the extracted `EchoIsland-Agent/services/controller` folder and run, using the robot's matching SDK Python:

```text
python -m echo_controller.robot_worker --config /YOUR/PRIVATE/PATH/current.robot.json
```

The example path must be replaced. Start with gestures off. Add `--gestures` only for a supervised antenna bench check after checking the physical pose. The worker refuses to run the Wireless output backend on Windows/macOS or without its explicit ALSA alias. There is no automatic default-speaker fallback.

Alternatively, from the extracted agent root use `bash Launch-Wireless-Agent.sh /YOUR/PRIVATE/PATH/current.robot.json`. Set `REACHY_AGENT_PYTHON` to the matching SDK Python path when necessary. This wrapper does not install packages, open SSH or change daemon settings itself.

5. Click **Begin** in the PC game and test a short line, pause/resume, skip/cancel, narrator handoff and disconnect before attempting the full adventure. Closing the game sends terminal stop; the worker exits, and the PC removes its local temporary capabilities. Remove the copied robot capability file after the session. Closing the SSH tunnel causes the worker to stop local output on request failure. Hardware stopping latency and speaker quality still require measurement.

## Microphone source

`Play-Controller.ps1 -Wireless -Microphone` uses the **PC's push-to-talk microphone**, not Reachy's microphone. It routes structured controls to the same game while the robot handles output. The robot microphone and WebRTC input are not silently enabled. On-robot speech capture can use the same speech worker and local Vosk model, but selecting/configuring and validating that physical input device remains a hardware task. Personal replies still use explicit completion/skip buttons; raw replies are not stored.

## Simulator limits

Without the robot, use `-BridgeSimulator` to exercise the entire common chapter/worker protocol. The simulator is silent and reports `simulated_completed`. It does not prove SSH reachability, Linux driver availability, real audio EOS, motor behavior, microphone quality or human conversation accuracy. Package tests do not make those claims either.

Personalized nickname audio now uses the optional local Kokoro renderer. The Windows simulator has been tested; physical Wireless has not. For nickname speech on another host, install kokoro-onnx 0.6.1 in a separate Python environment, set ECHO_VOICE_PYTHON to its interpreter and provision the official kokoro-v1.0.onnx and voices-v1.0.bin under tools/narration/kokoro. The agent ZIP includes fixed speech clips, not model weights or Python environments. No runtime download is attempted.
