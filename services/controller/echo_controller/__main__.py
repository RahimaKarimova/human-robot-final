"""Local development commands. Session capability is written to an ignored file."""
import argparse
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    serve = sub.add_parser("serve")
    serve.add_argument("--port", type=int, default=8765)
    start = sub.add_parser("new-session")
    start.add_argument("--port", type=int, default=8765)
    start.add_argument("--condition", choices=("control", "humour"), default="control")
    start.add_argument("--output", type=Path, required=True)
    start.add_argument("--preview", action="store_true", help="Draft welcome and Library voice rehearsal; no hardware")
    start.add_argument("--robot-output", choices=("laptop", "bridge_simulator", "reachy_lite", "reachy_wireless", "reachy_mujoco", "reachy_control_simulator"), default="laptop")
    start.add_argument("--robot-config", type=Path)
    start.add_argument("--speech-config", type=Path)
    start.add_argument("--conversation", action="store_true")
    start.add_argument("--push-to-talk", action="store_true", help="Conversation replies only while B is held; no automatic listening.")
    start.add_argument("--transcript", action="store_true", help="Private researcher transcript in transcripts/conversations.md.")
    start.add_argument("--survey-url", default="", help="Post-game survey link; the game shows it on the treasure screen.")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("Use a local unprivileged port between 1024 and 65535.")
    if args.action == "serve":
        import uvicorn
        uvicorn.run("echo_controller.app:app", host="127.0.0.1", port=args.port,
                    access_log=False, log_level="warning")
    else:
        if args.robot_output != "laptop" and (not args.preview or not args.robot_config):
            parser.error("External output requires --preview and a separate --robot-config file.")
        if args.robot_config and (args.robot_output == "laptop" or args.robot_config.resolve() == args.output.resolve()):
            parser.error("Use distinct game and robot configuration paths for external output.")
        if args.speech_config and args.speech_config.resolve() in {args.output.resolve(), args.robot_config.resolve() if args.robot_config else None}:
            parser.error("Use a distinct speech configuration path.")
        url = f"http://127.0.0.1:{args.port}"
        request = Request(url + "/session/start", data=json.dumps({"condition": args.condition, "mode": "mock", "preview": args.preview, "output": args.robot_output, "speech":bool(args.speech_config),"conversation":args.conversation,"push_to_talk":args.push_to_talk,"transcript":args.transcript}).encode(),
                          headers={"Content-Type": "application/json"}, method="POST")
        with urlopen(request, timeout=5) as response:
            session = json.load(response)
        # Do not include the condition, proposed question text or any participant data.
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", encoding="utf-8") as file:
            game_config = {"url": url, "session_id": session["session_id"], "token": session["token"], "preview": args.preview, "output": args.robot_output, "speech":bool(args.speech_config),"conversation":args.conversation}
            if args.survey_url.startswith("https://claude.ai/") and session.get("participant_id"):
                # The participant needs their own number for the survey; nothing else is shared.
                game_config["survey_url"] = args.survey_url.split("#")[0] + "#" + session["participant_id"]
            json.dump(game_config, file)
        if args.speech_config:
            args.speech_config.parent.mkdir(parents=True, exist_ok=True)
            args.speech_config.write_text(json.dumps({"url":url,"session_id":session["session_id"],"speech_token":session["speech_token"],"conversation":args.conversation}), encoding="utf-8")
            if os.name != "nt":
                args.speech_config.chmod(0o600)
        if args.robot_config:
            if args.robot_output == "laptop":
                parser.error("Robot configuration requires an external output route.")
            args.robot_config.parent.mkdir(parents=True, exist_ok=True)
            args.robot_config.write_text(json.dumps({"url": url, "session_id": session["session_id"],
                "robot_token": session["robot_token"], "output": args.robot_output}), encoding="utf-8")
            if os.name != "nt":
                args.robot_config.chmod(0o600)
        if os.name != "nt":
            args.output.chmod(0o600)
        if session.get("participant_id"):
            print(f"Participant ID: {session['participant_id']}. Conversation transcript: transcripts/conversations.md (private, not shown in game).")
            print(f"Development session created. Output route: {args.robot_output}. No audio is stored.")
        else:
            print(f"Development session created. Output route: {args.robot_output}. No audio or answer storage enabled.")


if __name__ == "__main__":
    main()
