# Simulation audit

UTC run: 20261113-141744
Overall: PASS

This audit uses silent simulation, bundled audio playback callbacks and synthetic speech fixtures. It does not open a live microphone or operate a robot.

| Check | Result | Log |
|---|---|---|
| Controller and live Rasa unit tests | PASS | [01-Controller-and-live-Rasa-unit-tests.log](simulation-audit/20261113-141744/01-Controller-and-live-Rasa-unit-tests.log) |
| Offline speech model with synthetic fixtures | PASS | [02-Offline-speech-model-with-synthetic-fixtures.log](simulation-audit/20261113-141744/02-Offline-speech-model-with-synthetic-fixtures.log) |
| Offline complete game | PASS | [03-Offline-complete-game.log](simulation-audit/20261113-141744/03-Offline-complete-game.log) |
| Full simulator campaign control | PASS | [04-Full-simulator-campaign-control.log](simulation-audit/20261113-141744/04-Full-simulator-campaign-control.log) |
| Real Rasa control routing control | PASS | [05-Real-Rasa-control-routing-control.log](simulation-audit/20261113-141744/05-Real-Rasa-control-routing-control.log) |
| Full simulator campaign humour | PASS | [06-Full-simulator-campaign-humour.log](simulation-audit/20261113-141744/06-Full-simulator-campaign-humour.log) |
| Real Rasa control routing humour | PASS | [07-Real-Rasa-control-routing-humour.log](simulation-audit/20261113-141744/07-Real-Rasa-control-routing-humour.log) |
| Bridge disconnect and narrator recovery | PASS | [08-Bridge-disconnect-and-narrator-recovery.log](simulation-audit/20261113-141744/08-Bridge-disconnect-and-narrator-recovery.log) |
| Full laptop playback campaign | PASS | [09-Full-laptop-playback-campaign.log](simulation-audit/20261113-141744/09-Full-laptop-playback-campaign.log) |
| Stop before Begin | PASS | [10-Stop-before-Begin.log](simulation-audit/20261113-141744/10-Stop-before-Begin.log) |
| Speech controls replies and cancellation | PASS | [11-Speech-controls-replies-and-cancellation.log](simulation-audit/20261113-141744/11-Speech-controls-replies-and-cancellation.log) |
| Rendered voice controls and reply panel | PASS | [12-Rendered-voice-controls-and-reply-panel.log](simulation-audit/20261113-141744/12-Rendered-voice-controls-and-reply-panel.log) |
| Wireless package rebuild | PASS | [13-Wireless-package-rebuild.log](simulation-audit/20261113-141744/13-Wireless-package-rebuild.log) |
| Wireless package integrity | PASS | [14-Wireless-package-integrity.log](simulation-audit/20261113-141744/14-Wireless-package-integrity.log) |

Physical robot audio/motion, native SDK/GStreamer/SSH, actual microphone devices and human speech accuracy remain unverified. These software checks are preparation for bench testing, not hardware acceptance.
