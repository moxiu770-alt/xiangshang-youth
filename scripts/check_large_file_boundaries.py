#!/usr/bin/env python3
"""Prevent already-split domain files from growing back into monoliths."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUDGET_PATH = ROOT / "qa/large_file_budgets.json"


def main() -> int:
    budgets = json.loads(BUDGET_PATH.read_text(encoding="utf-8"))
    failures: list[str] = []
    for relative, budget in budgets.items():
        path = ROOT / relative
        if not path.is_file():
            failures.append(f"MISSING {relative}")
            continue
        lines = sum(1 for _ in path.open(encoding="utf-8"))
        marker = "PASS" if lines <= budget else "BLOCK"
        print(f"[{marker}] {relative}: {lines}/{budget} lines")
        if lines > budget:
            failures.append(f"{relative} exceeds {budget} lines ({lines})")
    if failures:
        print("large-file boundary failed: " + "; ".join(failures))
        return 1
    print("large-file boundaries OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
