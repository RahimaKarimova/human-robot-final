"""Observe isolated official MuJoCo audit instances without sending movement commands."""
import json
from pathlib import Path
import time
from urllib.request import build_opener, ProxyHandler

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"artifacts/official-reachy"
opener=build_opener(ProxyHandler({}))
results={variant:{"port":port,"samples":0,"max_antenna_excursion":0.0,"baseline":None,"errors":0} for variant,port in (("control",8001),("humour",8002))}
deadline=time.monotonic()+430
while time.monotonic()<deadline:
    for variant,record in results.items():
        try:
            with opener.open(f"http://127.0.0.1:{record['port']}/api/state/full",timeout=1) as response:
                state=json.load(response)
            pose=state["antennas_position"]
            if record["baseline"] is None:
                record["baseline"]=pose
            record["max_antenna_excursion"]=max(record["max_antenna_excursion"],max(abs(a-b) for a,b in zip(pose,record["baseline"])))
            record["samples"]+=1
        except Exception:
            record["errors"]+=1
    complete=True
    for variant in results:
        log=OUT/(variant+".log")
        raw=log.read_bytes() if log.exists() else b""
        text=raw.decode("utf-16" if raw.startswith((b"\xff\xfe",b"\xfe\xff")) else "utf-8-sig",errors="replace")
        complete=complete and ("ECHO FULL COMPANION:" in text or "FAIL:" in text or "could not start" in text)
    if complete:
        break
    time.sleep(0.25)
for record in results.values():
    record["movement_observed"]=record["max_antenna_excursion"]>0.015
(OUT/"measured-motion.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
print(json.dumps(results,indent=2))
assert all(record["movement_observed"] and record["samples"]>10 for record in results.values()), "Official simulated movement was not observed in both runs"
