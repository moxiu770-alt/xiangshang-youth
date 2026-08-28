#!/usr/bin/env python3
"""Release readiness preflight for the mobile app and central service.

The preflight deliberately distinguishes local/demo, pilot and production.  A
local build may use MockRepository and placeholder values; pilot/production
must explicitly select the remote service and must not silently fall back to a
demo host.  Secrets are validated by shape only and are never printed.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER_HOSTS = {"api.example.com", "example.com", "localhost", "127.0.0.1"}
REQUIRED_PRODUCTION_SECRETS = {
    "MFA_ENCRYPTION_KEY": 32,
    "VERIFICATION_CODE_PEPPER": 32,
    "AUDIT_LOG_SIGNING_KEY": 32,
    "FIELD_DEVICE_SIGNING_ENCRYPTION_KEY": 32,
    "METRICS_TOKEN": 24,
}


def env(name: str) -> str:
    return os.environ.get(name, "").strip()


def add(checks: list[dict], name: str, ok: bool, detail: str, *, blocking: bool = True) -> None:
    checks.append({"name": name, "ok": bool(ok), "blocking": blocking, "detail": detail})


def https_url(value: str) -> bool:
    try:
        parsed = urlparse(value)
        return parsed.scheme == "https" and bool(parsed.netloc) and parsed.hostname not in PLACEHOLDER_HOSTS
    except ValueError:
        return False


def command_path(name: str) -> Path | None:
    """Resolve SDK binaries even if a desktop shell omitted Android SDK PATH."""
    resolved = shutil.which(name)
    if resolved:
        return Path(resolved)
    if name != "adb":
        return None
    for root in (env("ANDROID_HOME"), env("ANDROID_SDK_ROOT"), str(Path.home() / "Library/Android/sdk")):
        candidate = Path(root) / "platform-tools" / "adb" if root else None
        if candidate and candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=("local", "pilot", "production"), default="local")
    parser.add_argument("--json", dest="json_path", type=Path)
    parser.add_argument("--allow-missing-devices", action="store_true")
    args = parser.parse_args()

    checks: list[dict] = []
    strict = args.target != "local"
    android_gradle = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    ios_project = (ROOT / "ios/XiangshangYouth/XiangshangYouth.xcodeproj/project.pbxproj").read_text(encoding="utf-8")

    add(checks, "frontend-contract-script", (ROOT / "scripts/check_frontend_contract.py").is_file(), "跨端契约脚本存在")
    migration_sequence = subprocess.run(
        [sys.executable, str(ROOT / "scripts/check_migration_sequence.py")],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    migration_detail = (migration_sequence.stdout.strip().splitlines()[-1] if migration_sequence.stdout.strip() else "迁移序列检查未运行")
    add(checks, "migration-sequence", migration_sequence.returncode == 0, migration_detail)
    boundary_check = subprocess.run(
        [sys.executable, str(ROOT / "scripts/check_large_file_boundaries.py")],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    boundary_detail = (boundary_check.stdout.strip().splitlines()[-1] if boundary_check.stdout.strip() else "大文件边界检查未运行")
    add(checks, "domain-file-boundaries", boundary_check.returncode == 0, boundary_detail)
    add(checks, "privacy-manifest", (ROOT / "ios/XiangshangYouth/PrivacyInfo.xcprivacy").is_file(), "iOS 隐私清单存在")
    add(checks, "android-cleartext-disabled", 'android:usesCleartextTraffic="false"' in (ROOT / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8"), "Android 明文流量已禁止")
    add(checks, "android-release-guard", "Release build cannot use the placeholder" in android_gradle, "Android Release 会拦截占位地址和 Mock")
    add(checks, "ios-release-guard", "Release requires API_BASE_URL" in ios_project and "Release requires USE_REMOTE_DATA_SOURCE=1" in ios_project, "iOS Release 会拦截占位地址和 Mock")

    api_url = env("API_BASE_URL") or env("XS_API_BASE_URL")
    remote = env("USE_REMOTE_DATA_SOURCE") or env("XS_USE_REMOTE_DATA_SOURCE")
    if strict:
        add(checks, "remote-api-url", https_url(api_url), "API_BASE_URL 必须是非占位 HTTPS 地址")
        add(checks, "remote-data-source", remote.lower() in {"1", "true", "yes"}, "必须显式启用 RemoteRepository")
        rollout = env("ROLLOUT_CONFIG_URL") or env("ROLLOUT_CONFIG_URL_IOS") or env("ROLLOUT_CONFIG_URL_ANDROID")
        add(checks, "rollout-url", https_url(rollout), "灰度配置地址必须是非占位 HTTPS 地址")
        sentry = env("SENTRY_DSN") or env("SENTRY_DSN_IOS") or env("SENTRY_DSN_ANDROID")
        add(checks, "crash-dsn", sentry.startswith("https://") and "@" in sentry, "发布构建必须注入崩溃监控 DSN")
        for key, minimum in REQUIRED_PRODUCTION_SECRETS.items():
            value = env(key)
            ready = len(value) >= minimum and not value.lower().startswith("replace_with")
            detail = f"{key} 已注入且长度满足要求" if ready else f"{key} 未注入、长度不足或仍为占位值"
            add(checks, f"secret:{key}", ready, detail)
        add(checks, "storage-driver", env("FILE_STORAGE_DRIVER") == "s3" and bool(env("S3_BUCKET")), "正式环境使用对象存储并配置 bucket")
        add(checks, "backup", env("BACKUP_ENABLED").lower() == "true" and env("BACKUP_ARCHIVE_ENABLED").lower() == "true", "正式环境启用异地备份归档")
        add(checks, "cors", bool(env("CORS_ORIGIN")) and env("CORS_ORIGIN") != "*", "正式环境 CORS 不得为通配符")
        wechat_ready = bool(env("WECHAT_APP_ID")) and bool(env("WECHAT_APP_SECRET")) and https_url(env("WECHAT_REDIRECT_URI"))
        add(checks, "wechat-oauth", wechat_ready, "正式登录页的微信授权必须配置 AppID、Secret 和 HTTPS 回调地址")
    else:
        add(checks, "demo-mode-explicit", remote.lower() not in {"1", "true", "yes"} or bool(api_url), "本地允许 Mock；若切 Remote 必须自行提供 API 地址", blocking=False)

    model_corpus = ROOT / "qa/model_labeled_corpus.schema.json"
    model_approval_schema = ROOT / "qa/model_validation_approval.schema.json"
    repeatability_schema = ROOT / "qa/capture_repeatability.schema.json"
    model_verifier = ROOT / "scripts/verify_model_validation_approval.py"
    capture_profile_verifier = ROOT / "backend/scripts/verify-mobile-capture-calibration-registry.mjs"
    add(checks, "model-schema", model_corpus.is_file(), "人工标注集 schema 存在")
    add(checks, "model-approval-schema", model_approval_schema.is_file(), "模型人工审批 schema 存在")
    add(checks, "model-repeatability-schema", repeatability_schema.is_file(), "同人10次重复性验证 schema 存在")
    add(checks, "model-approval-verifier", model_verifier.is_file(), "模型人工审批验证脚本存在")
    add(checks, "capture-calibration-profile-verifier", capture_profile_verifier.is_file(), "物理标定配置验证脚本存在")
    if strict:
        verification = subprocess.run([sys.executable, str(model_verifier)], cwd=ROOT, text=True, capture_output=True, check=False)
        detail = (verification.stdout.strip() or verification.stderr.strip() or "模型人工验证失败").replace("\n", " ")
        if detail.startswith("[BLOCK] model-human-validation: "):
            detail = detail.removeprefix("[BLOCK] model-human-validation: ")
        add(checks, "model-human-validation", verification.returncode == 0, detail, blocking=True)
    else:
        add(checks, "model-human-validation", True, "本地模式仅验证门禁脚本；模型保持 pending-human-validation", blocking=False)

    capture_registry_path = env("MOBILE_CAPTURE_CALIBRATION_REGISTRY_PATH")
    if strict:
        if capture_registry_path and Path(capture_registry_path).is_file() and capture_profile_verifier.is_file():
            calibration = subprocess.run(
                ["node", str(capture_profile_verifier), "--input", capture_registry_path],
                cwd=ROOT / "backend", text=True, capture_output=True, check=False,
            )
            detail = (calibration.stdout.strip() or calibration.stderr.strip() or "物理标定配置验证失败").replace("\n", " ")
            add(checks, "capture-calibration-profile", calibration.returncode == 0, detail)
        else:
            add(checks, "capture-calibration-profile", False, "正式姿态发布需要 MOBILE_CAPTURE_CALIBRATION_REGISTRY_PATH 指向已批准的设备标定配置")
    else:
        add(checks, "capture-calibration-profile", True, "本地模式允许引导质量采集；物理标定配置尚未作为发布依据", blocking=False)

    git_remote = subprocess.run(["git", "config", "--get", "remote.origin.url"], cwd=ROOT, text=True, capture_output=True, check=False).stdout.strip()
    add(checks, "git-remote", bool(git_remote) or not strict, "正式发布需要受保护的 Git 远程仓库", blocking=strict)
    device_paths = {"xcrun": command_path("xcrun"), "adb": command_path("adb")}
    devices = {key: value is not None for key, value in device_paths.items()}
    device_detail = ", ".join(f"{key}={value if value else '未发现'}" for key, value in device_paths.items())
    add(checks, "device-tooling", all(devices.values()) or args.allow_missing_devices, device_detail, blocking=not args.allow_missing_devices)

    failed = [item for item in checks if item["blocking"] and not item["ok"]]
    result = {"target": args.target, "ok": not failed, "checks": checks}
    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for item in checks:
        marker = "PASS" if item["ok"] else ("BLOCK" if item["blocking"] else "WARN")
        print(f"[{marker}] {item['name']}: {item['detail']}")
    if failed:
        print(f"release preflight failed: {len(failed)} blocking check(s)", file=sys.stderr)
        return 1
    print(f"release preflight passed for {args.target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
