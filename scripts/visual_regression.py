#!/usr/bin/env python3
"""Compare release screenshots with approved, same-device baselines.

Reference screenshots are intentionally not synthesized from the current app:
that would make a visual regression test tautological.  The script requires a
manifest that names an approved baseline and actual screenshot for every
critical page. Pillow is used when available; a missing baseline or size
mismatch is always a blocking failure.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path


def image_metrics(expected: Path, actual: Path) -> tuple[float, int]:
    try:
        from PIL import Image, ImageChops, ImageStat
    except ImportError as error:  # pragma: no cover - CI installs Pillow
        raise RuntimeError("visual regression requires Pillow") from error
    with Image.open(expected).convert("RGBA") as left, Image.open(actual).convert("RGBA") as right:
        if left.size != right.size:
            raise ValueError(f"尺寸不同：baseline={left.size}, actual={right.size}")
        diff = ImageChops.difference(left, right)
        stat = ImageStat.Stat(diff)
        mean = sum(stat.mean) / len(stat.mean) / 255.0
        changed = sum(1 for pixel in diff.getdata() if max(pixel) > 8)
        total = left.width * left.height
        return mean, math.ceil(changed / total * 10000) / 10000


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    payload = json.loads(args.manifest.read_text(encoding="utf-8"))
    threshold = float(payload.get("maxMeanAbsoluteDifference", 0.015))
    max_changed = float(payload.get("maxChangedPixelRatio", 0.02))
    failures: list[str] = []
    results: list[dict] = []
    for entry in payload.get("screenshots", []):
        name = str(entry.get("name", "unnamed"))
        baseline = args.root / str(entry["baseline"])
        actual = args.root / str(entry["actual"])
        if not baseline.is_file() or not actual.is_file():
            failures.append(f"{name}: 缺少 baseline 或 actual（不能用缺图判定通过）")
            continue
        try:
            mean, changed = image_metrics(baseline, actual)
            results.append({"name": name, "meanAbsoluteDifference": mean, "changedPixelRatio": changed})
            if mean > threshold or changed > max_changed:
                failures.append(f"{name}: mean={mean:.5f}, changed={changed:.4f}")
        except (OSError, ValueError, RuntimeError) as error:
            failures.append(f"{name}: {error}")
    if not payload.get("screenshots"):
        failures.append("manifest 没有截图条目")
    print(json.dumps({"ok": not failures, "results": results, "failures": failures}, ensure_ascii=False, indent=2))
    if failures:
        print(f"visual regression failed: {len(failures)} blocking item(s)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
