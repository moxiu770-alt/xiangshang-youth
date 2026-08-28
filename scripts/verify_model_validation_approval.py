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
POSTURE_DOMAINS = (
    "spinal_alignment", "shoulder_pelvis", "head_upper_posture", "trunk_rotation",
    "dynamic_knee", "gait", "seated_posture", "foot_arch",
)


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
    parser.add_argument("--repeatability", type=Path, default=os.environ.get("MODEL_REPEATABILITY_CORPUS_PATH"))
    parser.add_argument("--repeatability-report", type=Path, default=os.environ.get("MODEL_REPEATABILITY_REPORT_PATH"))
    parser.add_argument("--posture-domain-reports", type=Path, default=os.environ.get("MODEL_POSTURE_DOMAIN_REPORT_DIR"))
    parser.add_argument("--allow-pending", action="store_true", help="仅供本地/CI 检查门禁脚本，不可用于试点或生产")
    args = parser.parse_args()

    if not args.approval or not args.corpus or not args.report or not args.repeatability or not args.repeatability_report or not args.posture_domain_reports:
        if args.allow_pending:
            print("[WARN] model-human-validation: 未注入私有人工标注集、评估报告和审批记录；模型保持 pending-human-validation")
            return 0
        return fail("缺少模型审批、人工标注集、评估报告、10次重复性数据、重复性报告或八类姿态独立报告目录")
    if not args.approval.is_file() or not args.corpus.is_file() or not args.report.is_file() or not args.repeatability.is_file() or not args.repeatability_report.is_file() or not args.posture_domain_reports.is_dir():
        return fail("审批记录、私有语料、评估报告、10次重复性验证文件或八类姿态报告目录不存在")

    try:
        approval = json.loads(args.approval.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return fail(f"审批记录不是合法 JSON：{error}")

    required = {"approvalVersion", "approvalId", "status", "datasetId", "corpusSha256", "evaluationReportSha256", "repeatabilityCorpusSha256", "repeatabilityReportSha256", "modelRegistryVersion", "modelVersions", "postureDomainValidation", "validationProtocol", "evaluatedAt", "approvers"}
    missing = sorted(required - set(approval))
    if missing:
        return fail(f"审批记录缺少字段：{', '.join(missing)}")
    if approval.get("approvalVersion") != "UY-MODEL-APPROVAL-1.1" or approval.get("status") != "human-validated":
        return fail("审批记录不是 human-validated 的 UY-MODEL-APPROVAL-1.1")
    if not isinstance(approval.get("approvalId"), str) or len(approval["approvalId"]) < 8 or not isinstance(approval.get("datasetId"), str) or not approval["datasetId"].strip():
        return fail("审批记录的 approvalId 或 datasetId 非法")
    if not all(isinstance(approval.get(key), str) and re.fullmatch(r"[a-fA-F0-9]{64}", approval[key]) for key in ("corpusSha256", "evaluationReportSha256", "repeatabilityCorpusSha256", "repeatabilityReportSha256")):
        return fail("审批记录的 SHA-256 摘要非法")
    if not valid_iso8601(approval.get("evaluatedAt")):
        return fail("审批记录的 evaluatedAt 不是 ISO-8601 时间")
    protocol = approval.get("validationProtocol")
    if not isinstance(protocol, dict):
        return fail("审批记录缺少人工验证协议")
    double_screened_fraction = protocol.get("doubleScreenedFraction")
    cohens_kappa = protocol.get("cohensKappa")
    if not isinstance(double_screened_fraction, (int, float)) or double_screened_fraction < 0.10:
        return fail("人工验证至少需要 10% 样本由两名筛查人员独立盲复测")
    if not isinstance(cohens_kappa, (int, float)) or cohens_kappa < 0.80 or cohens_kappa > 1:
        return fail("两名筛查人员的一致性 Kappa 必须达到 0.80")
    cohorts = protocol.get("ageThresholdCohorts")
    if not isinstance(cohorts, list):
        return fail("审批记录缺少按周岁统计的阈值研发样本量")
    counts = {
        row.get("ageYears"): row.get("sampleCount")
        for row in cohorts
        if isinstance(row, dict) and isinstance(row.get("ageYears"), int) and isinstance(row.get("sampleCount"), int)
    }
    missing_ages = [age for age in range(6, 19) if counts.get(age, 0) < 500]
    if missing_ages:
        return fail("年龄阈值发布前每个周岁年龄至少需要 500 例独立样本；未达标年龄：" + ", ".join(map(str, missing_ages)))
    approvers = approval.get("approvers")
    roles = {row.get("role") for row in approvers if isinstance(row, dict)} if isinstance(approvers, list) else set()
    if not isinstance(approvers, list) or len(approvers) < 2 or not {"algorithm-owner", "clinical-or-safety-reviewer"}.issubset(roles):
        return fail("审批至少需要算法负责人和安全/专业复核人两类独立签核")
    if any(not isinstance(row.get("reviewerId"), str) or not row["reviewerId"].strip() or not valid_iso8601(row.get("approvedAt")) for row in approvers if isinstance(row, dict)):
        return fail("审批人记录不完整")

    domain_approvals = approval.get("postureDomainValidation")
    if not isinstance(domain_approvals, dict) or set(domain_approvals) != set(POSTURE_DOMAINS):
        return fail("姿态审批必须且只能包含八个独立问题域")
    for domain in POSTURE_DOMAINS:
        record = domain_approvals.get(domain)
        if not isinstance(record, dict) or record.get("status") != "human-validated":
            return fail(f"{domain} 未完成独立人工验证")
        if not isinstance(record.get("datasetId"), str) or not record["datasetId"].strip():
            return fail(f"{domain} 缺少独立数据集标识")
        if not isinstance(record.get("sampleCount"), int) or record["sampleCount"] < 500:
            return fail(f"{domain} 独立盲测样本不足 500 例")
        if not valid_iso8601(record.get("evaluatedAt")):
            return fail(f"{domain} 缺少合法评估时间")
        report_hash = record.get("evaluationReportSha256")
        if not isinstance(report_hash, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", report_hash):
            return fail(f"{domain} 报告摘要非法")
        domain_report_path = args.posture_domain_reports / f"{domain}.json"
        if not domain_report_path.is_file() or sha256(domain_report_path) != report_hash.lower():
            return fail(f"{domain} 独立报告不存在或摘要不一致")
        try:
            domain_report = json.loads(domain_report_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            return fail(f"{domain} 独立报告不是合法 JSON：{error}")
        if (domain_report.get("domain") != domain
                or domain_report.get("status") != "human-validated"
                or domain_report.get("datasetId") != record["datasetId"]
                or domain_report.get("sampleCount") != record["sampleCount"]):
            return fail(f"{domain} 独立报告与审批记录不一致")
        metrics = domain_report.get("metrics")
        if not isinstance(metrics, dict):
            return fail(f"{domain} 缺少商业验收指标")
        thresholds = (("sensitivity", 0.85, None), ("specificity", 0.80, None),
                      ("negativePredictiveValue", 0.85, None), ("repeatabilityIcc", 0.85, None),
                      ("ungradableRate", None, 0.10))
        for metric, minimum, maximum in thresholds:
            value = metrics.get(metric)
            if not isinstance(value, (int, float)) or (minimum is not None and value < minimum) or (maximum is not None and value > maximum):
                bound = f"≥ {minimum:.2f}" if minimum is not None else f"≤ {maximum:.2f}"
                return fail(f"{domain} 的 {metric} 未达商业验收线 {bound}")

    try:
        registry_version, versions = registry_versions()
    except ValueError as error:
        return fail(str(error))
    if approval["modelRegistryVersion"] != registry_version or approval.get("modelVersions") != versions:
        return fail("审批对应的模型注册表或冻结模型版本已变化，需要重新进行独立验证")
    if (approval["corpusSha256"].lower() != sha256(args.corpus)
            or approval["evaluationReportSha256"].lower() != sha256(args.report)
            or approval["repeatabilityCorpusSha256"].lower() != sha256(args.repeatability)
            or approval["repeatabilityReportSha256"].lower() != sha256(args.repeatability_report)):
        return fail("人工标注、10次重复性数据或其评估报告摘要与审批记录不一致")

    command = ["node", "scripts/evaluate_model_corpus.mjs", "--corpus", str(args.corpus), "--require-labeled", "--release-gate", "--output", str(args.report)]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        return fail("独立验证集未通过评估门禁：" + (result.stderr.strip() or result.stdout.strip()))
    if approval["evaluationReportSha256"].lower() != sha256(args.report):
        return fail("评估器重新生成报告后摘要变化；请重新审核，不能复用旧审批")
    repeatability_command = ["node", "scripts/evaluate_capture_repeatability.mjs", "--input", str(args.repeatability), "--release-gate", "--output", str(args.repeatability_report)]
    repeatability_result = subprocess.run(repeatability_command, cwd=ROOT, text=True, capture_output=True, check=False)
    if repeatability_result.returncode != 0:
        return fail("同人10次重复性门禁未通过：" + (repeatability_result.stderr.strip() or repeatability_result.stdout.strip()))
    if approval["repeatabilityReportSha256"].lower() != sha256(args.repeatability_report):
        return fail("重复性评估器重新生成报告后摘要变化；请重新审核，不能复用旧审批")
    print(f"[PASS] model-human-validation: 审批 {approval['approvalId']} 已验证，数据集 {approval['datasetId']} 与冻结模型版本一致")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
