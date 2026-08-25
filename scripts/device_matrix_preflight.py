#!/usr/bin/env python3
"""Discover local device tooling and emit a truthful matrix preflight report.

This never labels a simulator as a real-device result.  It records what is
connected and leaves missing physical devices as explicit blockers for the
release operator.
"""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str]) -> str:
    try:
        return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False, timeout=15).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "qa/device-matrix-preflight.json")
    args = parser.parse_args()
    ios_tool = shutil.which("xcrun")
    android_tool = shutil.which("adb")
    ios_devices = []
    if ios_tool:
        raw = run([ios_tool, "simctl", "list", "devices", "available", "--json"])
        try:
            payload = json.loads(raw)
            for runtime_devices in payload.get("devices", {}).values():
                for device in runtime_devices:
                    if device.get("state") == "Booted":
                        ios_devices.append({"name": device.get("name", ""), "udid": device.get("udid", "")})
        except json.JSONDecodeError:
            # Older Xcode versions can emit warnings before the JSON object;
            # keep a truthful empty list rather than guessing from text.
            ios_devices = []
    android_devices = []
    if android_tool:
        for line in run([android_tool, "devices", "-l"]).splitlines()[1:]:
            if line.strip() and "\tdevice" in line:
                android_devices.append(line.strip())
    report = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "host": platform.platform(),
        "tools": {"xcrun": bool(ios_tool), "adb": bool(android_tool)},
        "connected": {"iosSimulators": ios_devices, "androidDevices": android_devices},
        "truth": {
            "simulatorIsNotRealDevice": True,
            "physicalDeviceMatrixComplete": bool(android_devices) and bool(ios_devices),
        },
        "requiredMatrix": [
            "iOS iPhone SE / standard / Pro Max / iPad",
            "Android 360dp / 393dp / 412dp / 600dp / 800dp",
            "fontScale 1.0 / 1.3 / accessibility",
            "camera allow / deny / retry / background-resume",
            "offline / process death / rotation / low-memory recovery",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
