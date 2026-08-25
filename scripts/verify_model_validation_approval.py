#!/usr/bin/env python3
"""Fail closed before a human-labelled model validation approval is released.

The validation corpus stays outside the source repository. This verifier ties
the private corpus and evaluator result to a reviewable approval record using
SHA-256 digests, and rejects approvals if frozen model versions have moved.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_MODELS = ("movement", "posture", "bmi", "height", "followAlong", "growth")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> int:
    print(f"[BLOCK] model-human-validation: {message}", file=sys.stderr)
    return 1


def registry_versions() -> tuple[str, dict[str, str]]:
    source = (ROOT / "backend/src/modelRegistry.js").read_text(encoding="utf-8")
    registry = re.search(r"MODEL_REGISTRY_VERSION\s*=\s*'([^']+)'", source)
    if not registry:
        raise ValueError("无法读取模型注册表版本")
    versions: dict[str, str] = {}
    for key in REQUIRED_MODELS:
        match = re.search(rf"{re.escape(key)}:\s*Object\.freeze\(\{{.*?algorithmVersion:\s*'([^']+)'", source, re.DOTALL)
        if not match:
            raise ValueError(f"无法读取 {key} 模型版本")
        versions[key] = match.group(1)
    return registry.group(1), versions


def valid_iso8601(value: object) -> bool:
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--approval", type=Path, default=os.environ.get("MODEL_VALIDATION_APPROVAL_PATH"))
    parser.add_argument("--corpus", type=Path, default=os.environ.get("MODEL_CORPUS_PATH"))
    parser.add_argument("--report", type=Path, default=os.environ.get("MODEL_VALIDATION_REPORT_PATH"))
    parser.add_argument("--allow-pending", action="store_true", help="仅供本地/CI 检查门禁脚本，不可用于试点或生产")
    args = parser.parse_args()

    if not args.approval or not args.corpus or not args.report:
        if args.allow_pending:
            print("[WARN] model-human-validation: 未注入私有人工标注集、评估报告和审批记录；模型保持 pending-human-validation")
            return 0
        return fail("缺少 MODEL_VALIDATION_APPROVAL_PATH、MODEL_CORPUS_PATH 或 MODEL_VALIDATION_REPORT_PATH")
    if not args.approval.is_file() or not args.corpus.is_file() or not args.report.is_file():
        return fail("审批记录、私有语料或评估报告文件不存在")

    try:
        approval = json.loads(args.approval.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return fail(f"审批记录不是合法 JSON：{error}")

    required = {"approvalVersion", "approvalId", "status", "datasetId", "corpusSha256", "evaluationReportSha256", "modelRegistryVersion", "modelVersions", "evaluatedAt", "approvers"}
    missing = sorted(required - set(approval))
    if missing:
        return fail(f"审批记录缺少字段：{', '.join(missing)}")
    if approval.get("approvalVersion") != "UY-MODEL-APPROVAL-1.0" or approval.get("status") != "human-validated":
        return fail("审批记录不是 human-validated 的 UY-MODEL-APPROVAL-1.0")
    if not isinstance(approval.get("approvalId"), str) or len(approval["approvalId"]) < 8 or not isinstance(approval.get("datasetId"), str) or not approval["datasetId"].strip():
        return fail("审批记录的 approvalId 或 datasetId 非法")
    if not all(isinstance(approval.get(key), str) and re.fullmatch(r"[a-fA-F0-9]{64}", approval[key]) for key in ("corpusSha256", "evaluationReportSha256")):
        return fail("审批记录的 SHA-256 摘要非法")
    if not valid_iso8601(approval.get("evaluatedAt")):
        return fail("审批记录的 evaluatedAt 不是 ISO-8601 时间")
    approvers = approval.get("approvers")
    roles = {row.get("role") for row in approvers if isinstance(row, dict)} if isinstance(approvers, list) else set()
    if not isinstance(approvers, list) or len(approvers) < 2 or not {"algorithm-owner", "clinical-or-safety-reviewer"}.issubset(roles):
        return fail("审批至少需要算法负责人和安全/专业复核人两类独立签核")
    if any(not isinstance(row.get("reviewerId"), str) or not row["reviewerId"].strip() or not valid_iso8601(row.get("approvedAt")) for row in approvers if isinstance(row, dict)):
        return fail("审批人记录不完整")

    try:
        registry_version, versions = registry_versions()
    except ValueError as error:
        return fail(str(error))
    if approval["modelRegistryVersion"] != registry_version or approval.get("modelVersions") != versions:
        return fail("审批对应的模型注册表或冻结模型版本已变化，需要重新进行独立验证")
    if approval["corpusSha256"].lower() != sha256(args.corpus) or approval["evaluationReportSha256"].lower() != sha256(args.report):
        return fail("私有语料或评估报告摘要与审批记录不一致")

    command = ["node", "scripts/evaluate_model_corpus.mjs", "--corpus", str(args.corpus), "--require-labeled", "--release-gate", "--output", str(args.report)]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        return fail("独立验证集未通过评估门禁：" + (result.stderr.strip() or result.stdout.strip()))
    if approval["evaluationReportSha256"].lower() != sha256(args.report):
        return fail("评估器重新生成报告后摘要变化；请重新审核，不能复用旧审批")
    print(f"[PASS] model-human-validation: 审批 {approval['approvalId']} 已验证，数据集 {approval['datasetId']} 与冻结模型版本一致")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
