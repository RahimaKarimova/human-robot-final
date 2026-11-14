"""Read-only MuJoCo display of the Control app's mock-simulator joint state.

Uses the official installed Reachy model. This is a visualization, not a second
robot controller or a physical-device validation. No microphone or media input.
"""
from importlib.resources import files
import json
import time
from urllib.request import build_opener, ProxyHandler
from urllib.error import URLError

import mujoco
import mujoco.viewer
import reachy_mini
from reachy_mini.daemon.backend.mujoco.utils import get_actuator_names, get_joint_addr_from_name

opener = build_opener(ProxyHandler({}))


def read(route):
    with opener.open("http://127.0.0.1:8000" + route, timeout=1) as response:
        return json.loads(response.read(65536))


def validate():
    status = read("/api/daemon/status")
    if status.get("mockup_sim_enabled") is not True or status.get("state") != "running":
        raise RuntimeError("Start the Control app mock simulator first; physical devices are not display targets.")


def main():
    validate()
    scene = files(reachy_mini).joinpath("descriptions/reachy_mini/mjcf/scenes/minimal.xml")
    model = mujoco.MjModel.from_xml_path(str(scene))
    data = mujoco.MjData(model)
    names = get_actuator_names(model)
    addresses = {name: get_joint_addr_from_name(model, name).item() for name in names}
    initialized = False
    checked = 0.0
    last_received = time.monotonic()
    with mujoco.viewer.launch_passive(model, data, show_left_ui=False, show_right_ui=False) as viewer:
        with viewer.lock():
            viewer.cam.distance = .65
            viewer.cam.azimuth = 160
            viewer.cam.elevation = -15
            viewer.cam.lookat[:] = [0, 0, .15]
        while viewer.is_running():
            try:
                if time.monotonic() - checked > 2:
                    validate()
                    checked = time.monotonic()
                state = read("/api/state/full?with_head_joints=true")
                last_received = time.monotonic()
            except (TimeoutError, OSError, URLError):
                # A transient local API delay must not destroy the viewer.
                # Retain the last pose; never synthesize movements while offline.
                if time.monotonic() - last_received > 15:
                    raise RuntimeError("Simulator state was unavailable for fifteen seconds.")
                viewer.sync()
                time.sleep(.2)
                continue
            antennas = state.get("antennas_position")
            if not isinstance(antennas, list) or len(antennas) != 2:
                raise RuntimeError("Simulator antenna state unavailable.")
            with viewer.lock():
                # The official MuJoCo backend uses opposite antenna signs to SDK.
                targets = {"right_antenna": -antennas[0], "left_antenna": -antennas[1]}
                head = state.get("head_joints")
                if isinstance(head, list) and len(head) == 7:
                    targets.update(zip(["yaw_body"]+[f"stewart_{i}" for i in range(1,7)], head))
                for name, value in targets.items():
                    data.ctrl[names.index(name)] = value
                    if not initialized or "antenna" in name:
                        data.qpos[addresses[name]] = value
                initialized = True
                # Settle the model's passive Stewart joints for the measured head
                # targets. This affects the display only; nothing is sent back.
                mujoco.mj_step(model, data, nstep=50)
            viewer.sync()
            time.sleep(.1)


if __name__ == "__main__":
    main()
