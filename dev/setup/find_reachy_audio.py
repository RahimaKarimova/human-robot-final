"""Find Reachy Mini's microphone index and speaker name on this laptop.

Run with the speech environment's Python. Prints one JSON line:
{"input": <sounddevice index or -1>, "speaker": "<full speaker name or ''>"}
Windows device numbers differ between laptops, so the study launcher asks
this script every time instead of using a fixed number.
"""
import json

import sounddevice as sd


def is_reachy(name):
    name = name.casefold()
    return "reachy" in name or "respeaker" in name


def main():
    devices = sd.query_devices()
    apis = [api["name"] for api in sd.query_hostapis()]
    # DirectSound was the reliable input on the study laptop; MME next.
    preference = ("Windows DirectSound", "MME", "Windows WASAPI")
    mic, speaker = -1, ""
    for api_name in preference:
        for index, device in enumerate(devices):
            if (device["max_input_channels"] > 0 and is_reachy(device["name"])
                    and apis[device["hostapi"]] == api_name):
                mic = index
                break
        if mic >= 0:
            break
    # WASAPI and DirectSound report the full endpoint name, which the robot
    # worker's GStreamer device search matches; MME names are cut short.
    for api_name in ("Windows WASAPI", "Windows DirectSound", "MME"):
        names = [d["name"] for d in devices
                 if d["max_output_channels"] > 0 and is_reachy(d["name"])
                 and apis[d["hostapi"]] == api_name]
        if names:
            speaker = max(names, key=len)
            break
    print(json.dumps({"input": mic, "speaker": speaker}))


if __name__ == "__main__":
    main()
