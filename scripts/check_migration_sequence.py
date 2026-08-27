#!/usr/bin/env python3
"""Keep new migration numbers unique without renaming applied legacy files."""

from collections import defaultdict
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "backend/db/migrations"
LEGACY_DUPLICATES = {
    "011": {"011_activity_appointment_lifecycle.sql", "011_runtime_heartbeats.sql"},
    "012": {"012_assessment_standard_snapshots.sql", "012_class_circle_health_observations.sql"},
}


def main() -> int:
    grouped: dict[str, set[str]] = defaultdict(set)
    failures: list[str] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        match = re.fullmatch(r"(\d{3})_[a-z0-9_]+\.sql", path.name)
        if not match:
            failures.append(f"命名不合法: {path.name}")
            continue
        grouped[match.group(1)].add(path.name)

    for version, names in grouped.items():
        if len(names) <= 1:
            continue
        if LEGACY_DUPLICATES.get(version) != names:
            failures.append(f"版本 {version} 重复: {', '.join(sorted(names))}")

    for version, expected in LEGACY_DUPLICATES.items():
        if grouped.get(version) != expected:
            failures.append(f"历史迁移 {version} 集合发生变化；已部署迁移不得重命名")

    if failures:
        print("migration sequence FAILED: " + "; ".join(failures))
        return 1
    print(f"migration sequence OK ({sum(len(names) for names in grouped.values())} files; legacy 011/012 frozen)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
