#!/usr/bin/env python3
"""Emit GitHub annotations for JUnit XML failures without hiding test details."""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def workflow_escape(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    report_title = sys.argv[2] if len(sys.argv) > 2 else "Android tests"
    files = sorted(root.rglob("TEST-*.xml")) if root.exists() else []
    failures: list[tuple[str, str]] = []
    for file in files:
        suite = ET.parse(file).getroot()
        for case in suite.findall(".//testcase"):
            failure = case.find("failure")
            if failure is None:
                failure = case.find("error")
            if failure is None:
                continue
            identity = ".".join(filter(None, [case.get("classname", ""), case.get("name", "")]))
            detail = (failure.get("message") or failure.text or "测试失败").strip()
            failures.append((identity or file.stem, detail))

    if not files:
        print(f"::error title={workflow_escape(report_title)}::未生成 JUnit XML：{workflow_escape(str(root))}")
    elif not failures:
        print(f"::error title={workflow_escape(report_title)}::Gradle 返回失败，但 JUnit XML 中没有失败用例，请检查编译或运行器日志")
    else:
        for identity, detail in failures:
            print(f"::error title={workflow_escape(identity)}::{workflow_escape(detail)}")
    print(f"JUnit XML files={len(files)}, failures={len(failures)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
