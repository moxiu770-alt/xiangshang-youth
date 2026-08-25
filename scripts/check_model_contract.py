#!/usr/bin/env python3
"""Fail fast when the iOS, Android and backend model contracts drift.

This is intentionally a small source-level guard, not an accuracy claim. The
runtime model tests cover behaviour; this check covers constants and age-band
boundaries that are otherwise easy to change in only one client.
"""

from pathlib import Path
import json
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
IOS_BODY = (ROOT / "ios/XiangshangYouth/Core/Models/BodyAssessment.swift").read_text()
ANDROID_BODY = (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/BodyAssessment.kt").read_text()
ANDROID_GROWTH = (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/GrowthInsight.kt").read_text()
IOS_SCORE = (ROOT / "ios/XiangshangYouth/Core/Models/DiagnosisReport.swift").read_text()
IOS_SCORE_RESULT = (ROOT / "ios/XiangshangYouth/Core/Models/ScoreResult.swift").read_text()
ANDROID_SCORE = (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/DiagnosisReport.kt").read_text()
ANDROID_SCORE_ADAPTER = (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/service/ScoreReviewStatusJsonAdapter.kt").read_text()
ANDROID_TASK = (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/BodyAssessment.kt").read_text()
BACKEND_SCORE = (ROOT / "backend/src/scoring.js").read_text()
BACKEND_SERVER = (ROOT / "backend/src/server.js").read_text()
BACKEND_POSTURE = (ROOT / "backend/src/postureScoring.js").read_text()
BACKEND_BODY = (ROOT / "backend/src/bodyScoring.js").read_text()
BACKEND_GROWTH = (ROOT / "backend/src/growthScoring.js").read_text()
BACKEND_REPORT_REFRESH = (ROOT / "backend/src/reportRefresh.js").read_text()
BACKEND_AGE = (ROOT / "backend/src/age.js").read_text()
BACKEND_CALIBRATION = (ROOT / "backend/src/modelCalibration.js").read_text()
BACKEND_REGISTRY = (ROOT / "backend/src/modelRegistry.js").read_text()
IOS_FOLLOW = (ROOT / "ios/XiangshangYouth/Features/Parent/FollowAlongTraining.swift").read_text()
IOS_GROWTH = (ROOT / "ios/XiangshangYouth/Core/Models/GrowthInsight.swift").read_text()
IOS_PROJECT = (ROOT / "ios/XiangshangYouth/XiangshangYouth.xcodeproj/project.pbxproj").read_text()
IOS_REMOTE = (ROOT / "ios/XiangshangYouth/Core/Repositories/RemoteRepository.swift").read_text()
ANDROID_FOLLOW = (
    (ROOT / "android/app/src/main/java/com/xiangshang/youth/feature/parent/FollowAlongTraining.kt").read_text()
    + "\n"
    + (ROOT / "android/app/src/main/java/com/xiangshang/youth/feature/parent/FollowAlongCaptureEngine.kt").read_text()
)
ANDROID_STUDENT_API = (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/service/StudentApi.kt").read_text()
ANDROID_REMOTE = (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/repository/RemoteRepository.kt").read_text()
MODEL_EVALUATOR = (ROOT / "scripts/evaluate_model_corpus.mjs").read_text()
MODEL_FUZZ = (ROOT / "scripts/fuzz_model_boundaries.mjs").read_text()
MODEL_FITTER = (ROOT / "scripts/fit_movement_calibration.mjs").read_text()
MODEL_FITTER_TEST = (ROOT / "scripts/test_model_calibration.mjs").read_text()
MODEL_FITTER_SCHEMA = json.loads((ROOT / "qa/model_calibration_corpus.schema.json").read_text())
MODEL_CORPUS = json.loads((ROOT / "qa/model_golden_corpus.json").read_text())
MODEL_SCHEMA = json.loads((ROOT / "qa/model_labeled_corpus.schema.json").read_text())
BODY_CAPTURE_ASSET = json.loads((ROOT / "android/app/src/main/assets/body_pose_capture_profiles.json").read_text())
FOLLOW_ACTION_ASSET = json.loads((ROOT / "android/app/src/main/assets/follow_along_action_profiles.json").read_text())


def require(pattern: str, source: str, label: str) -> None:
    if not re.search(pattern, source, flags=re.MULTILINE):
        raise AssertionError(f"model contract missing: {label}")


def extract_bmi_table(source: str, gender: str, android: bool = False, backend: bool = False):
    if android:
        pattern = rf"val {gender} = listOf\((.*?)\)\.map \{{ BmiRow"
        match = re.search(pattern, source, flags=re.DOTALL)
        if not match:
            raise AssertionError(f"BMI table missing: Android {gender}")
        rows = re.findall(r"(\d+)\s+to\s+([0-9.]+)\s+to\s+([0-9.]+)", match.group(1))
    elif backend:
        pattern = rf"const {gender} = Object\.freeze\(\[(.*?)\]\)"
        match = re.search(pattern, source, flags=re.DOTALL)
        if not match:
            raise AssertionError(f"BMI table missing: backend {gender}")
        rows = re.findall(r"(?:\[|\()(\d+),\s*([0-9.]+),\s*([0-9.]+)(?:\]|\))", match.group(1))
    else:
        pattern = rf"(?:static let|const) {gender}[^=]*= (?:Object\.freeze\()?\[(.*?)\]"
        match = re.search(pattern, source, flags=re.DOTALL)
        if not match:
            raise AssertionError(f"BMI table missing: {gender}")
        rows = re.findall(r"(?:\(|\[)(\d+),\s*([0-9.]+),\s*([0-9.]+)(?:\)|\])", match.group(1))
    parsed = [(int(month), float(attention), float(red)) for month, attention, red in rows]
    if len(parsed) != 25 or parsed[0][0] != 72 or parsed[-1][0] != 216:
        raise AssertionError(f"BMI table shape drifted for {gender}: {len(parsed)} rows")
    return parsed


def parse_numeric_named_arguments(source: str):
    number = r"[-+]?(?:\d+(?:\.\d+)?|\.\d+)"
    return {key: float(value) for key, value in re.findall(rf"([A-Za-z][A-Za-z0-9_]*)\s*(?::|=)\s*({number})", source)}


def extract_posture_profiles(source: str, platform: str):
    """Extract the executable posture scoring matrix for parity checks.

    The three implementations intentionally use different field spellings
    (for example `shoulderAttentionCentimeters` in Kotlin), so normalize only
    the suffixes here and compare the policy values, not source formatting.
    """
    if platform == "backend":
        section = source[source.index("const profiles"):source.index("const finite")]
        blocks = re.findall(
            r"\{\n\s*minMonths: (\d+), maxMonths: (\d+),(.*?)(?=\n\s*\},?\n\s*\{|\n\]\);)",
            section,
            flags=re.DOTALL,
        )
        return [((int(min_months), int(max_months)), parse_numeric_named_arguments(body)) for min_months, max_months, body in blocks]
    if platform == "ios":
        start = source.index("static func profile(ageMonths: Int?) -> ScoringProfile")
        section = source[start:source.index("/// Report-level rules")]
        blocks = re.findall(r"return ScoringProfile\(([^\)]*)\)", section, flags=re.DOTALL)
        bands = [(72, 96), (97, 132), (133, 180), (181, 216)]
        return list(zip(bands, (parse_numeric_named_arguments(block) for block in blocks)))
    if platform == "android":
        start = source.index("private val scoringProfiles")
        section = source[start:source.index("const val scoringWeightTotal")]
        blocks = re.findall(r"PostureScoringProfile\(\n(.*?)\n\s*\),?", section, flags=re.DOTALL)
        aliases = {
            "shoulderAttentionCentimeters": "shoulderAttention",
            "shoulderReferralCentimeters": "shoulderReferral",
            "pelvisAttentionCentimeters": "pelvisAttention",
            "pelvisReferralCentimeters": "pelvisReferral",
            "seatedMidlineAttentionCentimeters": "seatedMidlineAttention",
            "seatedRoundingAttentionDegrees": "seatedRoundingAttention",
            "forwardHeadAttentionDegrees": "forwardHeadAttention",
            "forwardHeadReferralDegrees": "forwardHeadReferral",
            "proxyAtrAttentionDegrees": "proxyAtrAttention",
            "proxyAtrReferralDegrees": "proxyAtrReferral",
            "ribProminenceEquivocalCentimeters": "ribProminenceEquivocalCentimeters",
            "ribProminencePositiveCentimeters": "ribProminencePositiveCentimeters",
            "gaitAttentionCentimeters": "gaitAttention",
        }
        parsed = []
        for block in blocks:
            values = parse_numeric_named_arguments(block)
            band = (int(values.pop("minMonths")), int(values.pop("maxMonths")))
            parsed.append((band, {aliases.get(key, key): value for key, value in values.items()}))
        return parsed
    raise AssertionError(f"unknown posture profile platform: {platform}")


def extract_height_table(source: str, gender: str, platform: str):
    """Read the 7–18 year height reference rows from each implementation."""
    if platform == "backend":
        section = source[source.index("const heightBoys"):source.index("export function normalizeGender")]
        match = re.search(rf"const height{gender.title()} = Object\.freeze\(\{{(.*?)\}}\);", section, flags=re.DOTALL)
        if not match:
            raise AssertionError(f"height table missing: backend {gender}")
        rows = re.findall(r"(\d+)\s*:\s*\[([^\]]+)\]", match.group(1))
    elif platform == "ios":
        section = source[source.index("private enum HeightReference"):]
        match = re.search(rf"static let {gender}: \[Int: Row\] = \[(.*?)\n\s*\]", section, flags=re.DOTALL)
        if not match:
            raise AssertionError(f"height table missing: iOS {gender}")
        rows = re.findall(r"(\d+)\s*:\s*Row\(([^\)]*)\)", match.group(1))
    elif platform == "android":
        section = source[source.index("private object HeightReference"):]
        match = re.search(rf"val {gender} = mapOf\((.*?)\n\s*\)", section, flags=re.DOTALL)
        if not match:
            raise AssertionError(f"height table missing: Android {gender}")
        rows = re.findall(r"(\d+)\s+to\s+Row\(([^\)]*)\)", match.group(1))
    else:
        raise AssertionError(f"unknown height table platform: {platform}")
    parsed = []
    for age, values in rows:
        numbers = [float(value) for value in re.findall(r"[-+]?(?:\d+(?:\.\d+)?|\.\d+)", values)]
        if len(numbers) != 5:
            raise AssertionError(f"height row shape drifted: {platform}/{gender}/{age}")
        parsed.append((int(age), tuple(numbers)))
    if len(parsed) != 12 or parsed[0][0] != 7 or parsed[-1][0] != 18:
        raise AssertionError(f"height table shape drifted: {platform}/{gender}")
    return parsed


def main() -> int:
    checks = [
        (r'static let algorithmVersion = "UY-IMCA-CV-1\.3"', IOS_BODY, "iOS posture algorithm version"),
        (r'const val algorithmVersion = "UY-IMCA-CV-1\.3"', ANDROID_BODY, "Android posture algorithm version"),
        (r'static let calibrationVersion = "UY-CAL-BASELINE-1\.0"', IOS_BODY, "iOS posture calibration version"),
        (r'const val calibrationVersion = "UY-CAL-BASELINE-1\.0"', ANDROID_BODY, "Android posture calibration version"),
        (r"POSTURE_ALGORITHM_VERSION.*from './postureScoring\.js'", BACKEND_SERVER, "backend posture algorithm wiring"),
        (r"scoreBodyAssessment.*from './bodyScoring\.js'", BACKEND_SERVER, "backend body scorer wiring"),
        (r"finiteScalar, scoreBodyAssessment.*from './bodyScoring\.js'", BACKEND_SERVER, "backend body API scalar gate wiring"),
        (r"export const POSTURE_ALGORITHM_VERSION = 'UY-IMCA-CV-1\.3'", BACKEND_POSTURE, "backend canonical posture scorer version"),
        (r"POSTURE_RULES_SOURCE_VERSION = 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20'", BACKEND_POSTURE, "backend posture framework source version"),
        (r"rulesSourceVersion: 'UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20'", BACKEND_REGISTRY, "posture registry framework source version"),
        (r"sourceVersion: 'android-v1-search-calibrated-2026-09-15'", BACKEND_REGISTRY, "posture capture source asset version"),
        (r"export const BMI_RULE_VERSION = 'WS/T 586—2018 年龄别 BMI 参考 v1\.1'", BACKEND_BODY, "backend canonical BMI rule version"),
        (r"export function combineBodyLevel", BACKEND_BODY, "backend BMI/posture level merge"),
        (r"validLevels = new Set", BACKEND_BODY, "backend unknown body level fail-closed gate"),
        (r"height >= 90 && height <= 190", BACKEND_BODY, "backend BMI physical height gate"),
        (r"weight >= 15 && weight <= 90", BACKEND_BODY, "backend BMI physical weight gate"),
        (r"const finiteScalar = \(value\) =>", BACKEND_BODY, "backend BMI scalar numeric gate"),
        (r"const height = finiteScalar\(input\.heightCm\)", BACKEND_SERVER, "backend body API height scalar gate"),
        (r"const sampleCount = finiteScalar\(snapshot\?\.sampleCount\)", BACKEND_SERVER, "backend body API posture sample scalar gate"),
        (r"postureLevel === 'unavailable'", BACKEND_BODY, "backend unavailable posture merge"),
        (r"export function normalizeTotalScore", BACKEND_SCORE, "backend canonical total score rounding"),
        (r"normalizeTotalScore\(value\)", BACKEND_SERVER, "server total score normalization"),
        (r"static func total\(_ value: Double\)", IOS_SCORE, "iOS aggregate total score normalization"),
        (r"AssessmentScoreRules\.total\(normalizedScores", IOS_SCORE, "iOS report uses canonical total normalization"),
        (r"fun total\(value: Double\)", ANDROID_SCORE, "Android aggregate total score normalization"),
        (r"AssessmentScoreRules\.total\(normalizedScores", ANDROID_SCORE, "Android report uses canonical total normalization"),
        (r"roundHalfUp\(rawValue, 1\)", BACKEND_BODY, "backend BMI one-decimal comparison"),
        (r"floor\(bmi \* 10 \+ 0\.5\) / 10", IOS_BODY, "iOS BMI half-up comparison"),
        (r"floor\(bmi \* 10\.0 \+ 0\.5\) / 10\.0", ANDROID_BODY, "Android BMI half-up comparison"),
        (r"export const HEIGHT_RULE_VERSION = 'WS/T 612—2018'", BACKEND_BODY, "backend canonical height rule version"),
        (r"BMI_ALGORITHM_VERSION = MODEL_REGISTRY\.bmi\.algorithmVersion", BACKEND_BODY, "backend BMI algorithm registry"),
        (r"HEIGHT_ALGORITHM_VERSION = MODEL_REGISTRY\.height\.algorithmVersion", BACKEND_BODY, "backend height algorithm registry"),
        (r"bmiAlgorithmVersion: BMI_ALGORITHM_VERSION", BACKEND_BODY, "backend BMI output version"),
        (r"bmiAgeBucketMonths: bmiAgeBucket", BACKEND_BODY, "backend BMI half-year audit bucket"),
        (r"ageMonths: Number\.isInteger\(ageMonths\) \? ageMonths : null", BACKEND_BODY, "body measurement age snapshot"),
        (r"heightAlgorithmVersion: HEIGHT_ALGORITHM_VERSION", BACKEND_BODY, "backend height output version"),
        (r"MODEL_REGISTRY_VERSION = 'UY-MODELS-1\.0'", BACKEND_REGISTRY, "model registry version"),
        (r"followAlong: Object\.freeze", BACKEND_REGISTRY, "follow-along registry entry"),
        (r"sourceVersion: 'android-child-precision-2026-09-16-child-motion-research-v4\.1'", BACKEND_REGISTRY, "follow-along source asset version"),
        (r"growth: Object\.freeze", BACKEND_REGISTRY, "growth registry entry"),
        (r"short-lived parser per call", IOS_GROWTH, "iOS growth date parser concurrency safety"),
        (r"export function heightDevelopment", BACKEND_BODY, "backend height development scorer"),
        (r"export const GROWTH_ALGORITHM_VERSION = 'UY-GROWTH-RULE-1\.1'", BACKEND_GROWTH, "backend canonical growth scorer version"),
        (r"export function scoreGrowth", BACKEND_GROWTH, "backend canonical growth scorer"),
        (r"Asia/Shanghai", BACKEND_GROWTH, "backend growth business timezone"),
        (r"if \(!\(value instanceof Date\) \|\| !Number\.isFinite\(value\.getTime\(\)\)\)", BACKEND_GROWTH, "backend growth invalid time gate"),
        (r"cameraProxyRibProminenceCm", BACKEND_POSTURE, "backend numeric rib-prominence evidence"),
        (r"camera ATR proxy", BACKEND_POSTURE, "backend camera ATR safety boundary"),
        (r"POSTURE_METRIC_LIMITS", BACKEND_POSTURE, "backend posture metric range gate"),
        (r"typeof value === 'string' && value\.trim\(\) === ''", BACKEND_POSTURE, "backend posture empty metric gate"),
        (r"Number\.isInteger\(snapshot\.sampleCount\)", BACKEND_POSTURE, "backend posture sample-count gate"),
        (r"metricsValid", BACKEND_POSTURE, "backend posture invalid metric pending gate"),
        (r"snapshotHasMetricEvidence", BACKEND_POSTURE, "backend posture evidence presence gate"),
        (r"headTiltYellow", BACKEND_POSTURE, "backend head-tilt screening rule"),
        (r"thoracicAtrDegrees", BACKEND_POSTURE, "backend thoracic ATR field"),
        (r"lumbarAtrDegrees", BACKEND_POSTURE, "backend lumbar ATR field"),
        (r"clamp out-of-scope ages", BACKEND_POSTURE, "backend posture age profile clamp"),
        (r"validMetrics", IOS_BODY, "iOS posture metric range gate"),
        (r"rulesSourceVersion = \"UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20\"", IOS_BODY, "iOS posture framework source version"),
        (r"thoracicAtrDegrees", IOS_BODY, "iOS thoracic ATR field"),
        (r"headTiltYellow", IOS_BODY, "iOS head-tilt screening rule"),
        (r"let rulesSourceVersion: String", IOS_BODY, "iOS posture report source version"),
        (r"loadCanonicalProfilesIfAvailable", IOS_BODY, "iOS posture capture canonical asset loader"),
        (r"canonicalAssetVersion = \"android-v1-search-calibrated-2026-09-15\"", IOS_BODY, "iOS posture capture asset version gate"),
        (r"canonicalProfileIsValid", IOS_BODY, "iOS posture capture complete asset bounds gate"),
        (r"validMetrics", ANDROID_BODY, "Android posture metric range gate"),
        (r"rulesSourceVersion = \"UY-IMCA-SCOLIOSIS-FRAMEWORK-V1-2026-07-20\"", ANDROID_BODY, "Android posture framework source version"),
        (r"thoracicAtrDegrees", ANDROID_BODY, "Android thoracic ATR field"),
        (r"headTiltYellow", ANDROID_BODY, "Android head-tilt screening rule"),
        (r"val rulesSourceVersion: String", ANDROID_BODY, "Android posture report source version"),
        (r"let rulesSourceVersion: String\?", IOS_REMOTE, "iOS remote posture source version decode"),
        (r"rulesSourceVersion: summary\.rulesSourceVersion", IOS_REMOTE, "iOS remote posture source version propagation"),
        (r"unsupportedAlgorithm\(summary\.algorithm\)", IOS_REMOTE, "iOS remote model algorithm fail-closed gate"),
        (r"summary\.calibrationVersion == PostureAssessmentReport\.calibrationVersion", IOS_REMOTE, "iOS remote calibration fail-closed gate"),
        (r"summary\.rulesSourceVersion == PostureScreeningRules\.rulesSourceVersion", IOS_REMOTE, "iOS remote rules fail-closed gate"),
        (r"let bmiAlgorithmVersion: String\?", IOS_REMOTE, "iOS remote BMI version decode"),
        (r"let heightAlgorithmVersion: String\?", IOS_REMOTE, "iOS remote height version decode"),
        (r"let modelRegistryVersion: String\?", IOS_REMOTE, "iOS remote registry version decode"),
        (r"unsupportedBMI\(response\.bmiAlgorithmVersion", IOS_REMOTE, "iOS remote BMI fail-closed gate"),
        (r"unsupportedHeight\(response\.heightAlgorithmVersion", IOS_REMOTE, "iOS remote height fail-closed gate"),
        (r"unsupportedRegistry\(response\.modelRegistryVersion", IOS_REMOTE, "iOS remote registry fail-closed gate"),
        (r"val rulesSourceVersion: String\? = null", ANDROID_STUDENT_API, "Android remote posture source version decode"),
        (r"val bmiAlgorithmVersion: String\? = null", ANDROID_STUDENT_API, "Android remote BMI version decode"),
        (r"val heightAlgorithmVersion: String\? = null", ANDROID_STUDENT_API, "Android remote height version decode"),
        (r"val modelRegistryVersion: String\? = null", ANDROID_STUDENT_API, "Android remote registry version decode"),
        (r"rulesSourceVersion = summary\.rulesSourceVersion", ANDROID_REMOTE, "Android remote posture source version propagation"),
        (r"(?:require\(response\.bmiAlgorithmVersion == BodyAssessmentRecord\.bmiAlgorithmVersion|if \(response\.bmiAlgorithmVersion != BodyAssessmentRecord\.bmiAlgorithmVersion\)\s*\{\s*throw ApiError\.ModelContract)", ANDROID_REMOTE, "Android remote BMI fail-closed gate"),
        (r"(?:require\(response\.heightAlgorithmVersion == BodyAssessmentRecord\.heightAlgorithmVersion|if \(response\.heightAlgorithmVersion != BodyAssessmentRecord\.heightAlgorithmVersion\)\s*\{\s*throw ApiError\.ModelContract)", ANDROID_REMOTE, "Android remote height fail-closed gate"),
        (r"(?:require\(response\.modelRegistryVersion == AssessmentScoreRules\.modelRegistryVersion|if \(response\.modelRegistryVersion != AssessmentScoreRules\.modelRegistryVersion\)\s*\{\s*throw ApiError\.ModelContract)", ANDROID_REMOTE, "Android remote registry fail-closed gate"),
        (r"(?:require\(summary\.algorithm == PostureAssessmentReport\.algorithmVersion|if \(summary\.algorithm != PostureAssessmentReport\.algorithmVersion\)\s*\{\s*throw ApiError\.ModelContract)", ANDROID_REMOTE, "Android remote model algorithm fail-closed gate"),
        (r"(?:require\(summary\.calibrationVersion == PostureAssessmentReport\.calibrationVersion|if \(summary\.calibrationVersion != PostureAssessmentReport\.calibrationVersion\)\s*\{\s*throw ApiError\.ModelContract)", ANDROID_REMOTE, "Android remote calibration fail-closed gate"),
        (r"(?:require\(summary\.rulesSourceVersion == PostureScreeningRules\.rulesSourceVersion|if \(summary\.rulesSourceVersion != PostureScreeningRules\.rulesSourceVersion\)\s*\{\s*throw ApiError\.ModelContract)", ANDROID_REMOTE, "Android remote rules fail-closed gate"),
        (r"profile\.ribProminencePositiveCentimeters", IOS_BODY, "iOS age-specific rib-prominence scoring"),
        (r"profile\.ribProminencePositiveCentimeters", ANDROID_BODY, "Android age-specific rib-prominence scoring"),
        (r"scoreBodyAssessment", MODEL_EVALUATOR, "offline model evaluator body path"),
        (r"evaluateMovementScores", MODEL_EVALUATOR, "offline model evaluator movement path"),
        (r"scoreGrowth", MODEL_EVALUATOR, "offline model evaluator growth path"),
        (r"--require-labeled", MODEL_EVALUATOR, "independent labeled-set gate"),
        (r"--release-gate", MODEL_EVALUATOR, "release accuracy and stratification gate"),
        (r"20 条样本", (ROOT / "qa/MODEL_VALIDATION.md").read_text(), "release minimum age-band sample gate"),
        (r"Number\(sample\.heightCm\) < 90", MODEL_EVALUATOR, "labeled body height physical gate"),
        (r'"minimum": 90, "maximum": 190', (ROOT / "qa/model_labeled_corpus.schema.json").read_text(), "labeled body height schema gate"),
        (r"balancedAccuracy", MODEL_EVALUATOR, "balanced model metrics"),
        (r"function metricsByTask", MODEL_EVALUATOR, "per-model release metrics"),
        (r"requiredTasks = \['movement', 'body', 'bmi', 'height', 'posture', 'growth', 'followAlong'\]", MODEL_EVALUATOR, "all model families release gate"),
        (r"followAlongMae", MODEL_EVALUATOR, "follow-along count error gate"),
        (r"function followAgeBand\(ageMonths\)", MODEL_EVALUATOR, "follow-along runtime age-band gate"),
        (r"age >= 133 && age <= 168", MODEL_EVALUATOR, "follow-along adolescent age-band boundary"),
        (r"age >= 169 && age <= 216", MODEL_EVALUATOR, "follow-along teen age-band boundary"),
        (r"JSON arrays/objects/booleans/blank strings are malformed", MODEL_EVALUATOR, "evaluator malformed numeric gate"),
        (r'"followAlong"', (ROOT / "qa/model_labeled_corpus.schema.json").read_text(), "follow-along labeled corpus schema"),
        (r"taskStrata", MODEL_EVALUATOR, "per-model stratified release metrics"),
        (r"stratumFor", MODEL_EVALUATOR, "stratified model metrics"),
        (r"clipHash", MODEL_EVALUATOR, "dataset leakage guard"),
        (r"fuzzCases", MODEL_FUZZ, "deterministic model boundary fuzz gate"),
        (r"posture risk regressed", MODEL_FUZZ, "posture risk monotonicity property"),
        (r"movement risk worsened", MODEL_FUZZ, "movement monotonicity property"),
        (r"BMI threshold regressed", MODEL_FUZZ, "BMI monotonicity property"),
        (r"height threshold regressed", MODEL_FUZZ, "height monotonicity property"),
        (r"跟做动态门限关系非法", MODEL_EVALUATOR, "follow-along dynamic gate relationship"),
        (r"candidate-review-required", MODEL_FITTER, "calibration candidate review gate"),
        (r"train/validation 泄漏", MODEL_FITTER, "calibration split leakage guard"),
        (r"fitMovementCalibration", MODEL_FITTER, "movement calibration fitter"),
        (r"candidate-review-required", MODEL_FITTER_TEST, "calibration fitter regression test"),
        (r"BUSINESS_TIME_ZONE = 'Asia/Shanghai'", BACKEND_AGE, "backend business timezone"),
        (r"MODEL_CALIBRATION_STATUS = 'pending-human-validation'", BACKEND_CALIBRATION, "calibration status gate"),
        (r"movementReviewConfidence: 0\.80", BACKEND_CALIBRATION, "movement calibration parameter"),
        (r"movementDuplicateConflictThreshold: 1\.5", BACKEND_CALIBRATION, "movement duplicate conflict calibration parameter"),
        (r"postureMinimumConfidence: 0\.56", BACKEND_CALIBRATION, "posture calibration parameter"),
        (r"timeZone = TimeZone\(identifier: \"Asia/Shanghai\"\)", IOS_BODY, "iOS business timezone"),
        (r"static func ageMonths\(from rawBirthDate", IOS_BODY, "iOS deterministic age seam"),
        (r'normalized\.range\(of: #"\^\\d\{4\}-\\d\{2\}-\\d\{2\}\$"#', IOS_BODY, "iOS strict birthday date shape gate"),
        (r"TimeZone\.getTimeZone\(\"Asia/Shanghai\"\)", ANDROID_BODY, "Android business timezone"),
        (r"fun ageMonthsFromBirthDate\(rawBirthDate", ANDROID_BODY, "Android deterministic age seam"),
        (r'if \(!Regex\("\^\\\\d\{4\}-\\\\d\{2\}-\\\\d\{2\}\$"\)\.matches\(raw\)\)', ANDROID_BODY, "Android strict birthday date shape gate"),
        (r'static let bmiSupportedAgeMonths = 72\.\.\.216', IOS_BODY, "iOS BMI supported ages"),
        (r'val bmiSupportedAgeMonths = 72\.\.216', ANDROID_BODY, "Android BMI supported ages"),
        (r'static let itemCount = TestItem\.allCases\.count', IOS_SCORE, "iOS seven-item count source"),
        (r'const val itemCount = 7', ANDROID_SCORE, "Android seven-item count"),
        (r"itemCount: MOVEMENT_ITEM_CODES\.length", BACKEND_SCORE, "backend seven-item count"),
        (r"MOVEMENT_ALGORITHM_VERSION = 'UY-IMCA-SCORE-1\.3'", BACKEND_SCORE, "backend movement algorithm version"),
        (r'static let algorithmVersion = "UY-IMCA-SCORE-1\.3"', IOS_SCORE, "iOS movement algorithm version"),
        (r'const val algorithmVersion = "UY-IMCA-SCORE-1\.3"', ANDROID_SCORE, "Android movement algorithm version"),
        (r"duplicateConflictThreshold", BACKEND_SCORE, "backend movement duplicate conflict gate"),
        (r"Only the explicit `passed` state may leave the", BACKEND_SCORE, "backend movement unknown review status gate"),
        (r"unsupportedAlgorithmVersion", BACKEND_SCORE, "backend movement stale algorithm review gate"),
        (r"algorithm_version AS \"algorithmVersion\"", BACKEND_REPORT_REFRESH, "backend report refresh algorithm version input"),
        (r"JSON `null`, booleans, empty strings and arrays", BACKEND_SCORE, "backend movement malformed numeric gate"),
        (r"JSON arrays/objects/functions coerce to numeric zero", BACKEND_POSTURE, "backend posture malformed numeric gate"),
        (r"malformed JSON values from becoming zero", BACKEND_GROWTH, "backend growth malformed numeric gate"),
        (r"SimpleDateFormat is mutable and not thread-safe", ANDROID_GROWTH, "Android growth parser concurrency note"),
        (r"decodeIfPresent\(String\.self, forKey: \.reviewStatus\)", IOS_SCORE_RESULT, "iOS unknown review status decode gate"),
        (r"ScoreReviewStatus\.PendingReview", ANDROID_SCORE_ADAPTER, "Android unknown review status fallback"),
        (r"duplicateConflictThreshold", IOS_SCORE, "iOS movement duplicate conflict gate"),
        (r"duplicateConflictThreshold", ANDROID_SCORE, "Android movement duplicate conflict gate"),
        (r'static let modelRegistryVersion = "UY-MODELS-1\.0"', IOS_SCORE, "iOS model registry version"),
        (r'const val modelRegistryVersion = "UY-MODELS-1\.0"', ANDROID_SCORE, "Android model registry version"),
        (r'static let calibrationVersion = "UY-CAL-BASELINE-1\.0"', IOS_SCORE, "iOS movement calibration version"),
        (r'const val calibrationVersion = "UY-CAL-BASELINE-1\.0"', ANDROID_SCORE, "Android movement calibration version"),
        (r'modelRegistryVersion: MODEL_REGISTRY_VERSION', BACKEND_SCORE, "backend movement registry output"),
        (r'modelRegistryVersion: MODEL_REGISTRY_VERSION', BACKEND_SERVER, "backend movement report registry output"),
        (r'var modelRegistryVersion: String\? = AssessmentScoreRules\.modelRegistryVersion', IOS_SCORE, "iOS movement report registry output"),
        (r'val modelRegistryVersion: String = AssessmentScoreRules\.modelRegistryVersion', ANDROID_SCORE, "Android movement report registry output"),
        (r'static let bmiAlgorithmVersion = "UY-IMCA-BMI-1\.2"', IOS_BODY, "iOS BMI algorithm version"),
        (r'const val bmiAlgorithmVersion = "UY-IMCA-BMI-1\.2"', ANDROID_BODY, "Android BMI algorithm version"),
        (r'static let heightAlgorithmVersion = "UY-IMCA-HEIGHT-1\.0"', IOS_BODY, "iOS height algorithm version"),
        (r'const val heightAlgorithmVersion = "UY-IMCA-HEIGHT-1\.0"', ANDROID_BODY, "Android height algorithm version"),
        (r'static let algorithmVersion = "UY-FOLLOW-CV-1\.0"', IOS_FOLLOW, "iOS follow-along algorithm version"),
        (r"loadCanonicalProfilesIfAvailable", IOS_FOLLOW, "iOS follow-along canonical asset loader"),
        (r"canonicalActionProfile", IOS_FOLLOW, "iOS follow-along age/action profile lookup"),
        (r"canonicalAssetVersion", IOS_FOLLOW, "iOS follow-along asset version gate"),
        (r"canonicalManifestIsValid", IOS_FOLLOW, "iOS follow-along complete asset bounds gate"),
        (r"expectedCategories: Set<String>", IOS_FOLLOW, "iOS follow-along complete action categories"),
        (r"expectedBands.contains", IOS_FOLLOW, "iOS follow-along complete action age bands"),
        (r"canonicalAssetVersion", ANDROID_FOLLOW, "Android follow-along asset version gate"),
        (r"isCanonicalManifest", ANDROID_FOLLOW, "Android follow-along complete asset gate"),
        (r"assetVersion.*canonicalAssetVersion", ANDROID_BODY, "Android posture asset version gate"),
        (r"incomplete posture capture canonical asset", ANDROID_BODY, "Android posture complete asset gate"),
        (r"private var confidenceHistory: \[Double\]", IOS_FOLLOW, "iOS follow-along confidence window"),
        (r"private func robustDerivative\(", IOS_FOLLOW, "iOS follow-along robust derivative gate"),
        (r"private func robustBounds\(", IOS_FOLLOW, "iOS follow-along trimmed dynamic range gate"),
        (r"private var stateReady = true", IOS_FOLLOW, "iOS follow-along hysteresis state"),
        (r"requiredSignalHistoryFrames", IOS_FOLLOW, "iOS follow-along warm-up history gate"),
        (r"returnSlopeMinRatio", IOS_FOLLOW, "iOS follow-along return slope gate"),
        (r"dynamicGateFloor", IOS_FOLLOW, "iOS follow-along age dynamic gate floor"),
        (r"minRange\.coerceAtMost\(rangeCeiling\)", ANDROID_FOLLOW, "Android follow-along safe dynamic range bounds"),
        (r"static func range\(_ values: \[Double\]\)", IOS_BODY, "iOS gait motion range helper"),
        (r"fun range\(values: List<Double>\)", ANDROID_BODY, "Android gait motion range helper"),
        (r"TASK_EVIDENCE_KEYS", BACKEND_POSTURE, "backend task-specific posture evidence gate"),
        (r"var isComplete: Bool", IOS_BODY, "iOS persisted posture completeness gate"),
        (r"movedFrames >= p\.gaitMovementWindowFrames", IOS_BODY, "iOS gait complete movement window"),
        (r"val confidenceHistory = ArrayDeque<Float>", ANDROID_FOLLOW, "Android follow-along confidence window"),
        (r"private fun robustDerivative\(", ANDROID_FOLLOW, "Android follow-along robust derivative gate"),
        (r"private fun robustRange\(", ANDROID_FOLLOW, "Android follow-along trimmed dynamic range gate"),
        (r"private var stateReady = true", ANDROID_FOLLOW, "Android follow-along hysteresis state"),
        (r"returnSlopeMinRatio", ANDROID_FOLLOW, "Android follow-along return slope gate"),
        (r"movementSamples >= profile\.gaitMovementWindowFrames", ANDROID_BODY, "Android gait complete movement window"),
        (r"Shared model assets", IOS_PROJECT, "iOS shared follow-along asset build phase"),
        (r"body_pose_capture_profiles\.json", IOS_PROJECT, "iOS shared posture capture asset build phase"),
        (r'const val algorithmVersion = "UY-FOLLOW-CV-1\.0"', ANDROID_FOLLOW, "Android follow-along algorithm version"),
        (r'static let algorithmVersion = "UY-GROWTH-RULE-1\.1"', (ROOT / "ios/XiangshangYouth/Core/Models/GrowthInsight.swift").read_text(), "iOS growth algorithm version"),
        (r'const val algorithmVersion = "UY-GROWTH-RULE-1\.1"', (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/GrowthInsight.kt").read_text(), "Android growth algorithm version"),
        (r'calendar\.timeZone = businessTimeZone', (ROOT / "ios/XiangshangYouth/Core/Models/GrowthInsight.swift").read_text(), "iOS growth business timezone"),
        (r'TimeZone\.getTimeZone\("Asia/Shanghai"\)', (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/GrowthInsight.kt").read_text(), "Android growth business timezone"),
        (r'normalized\.range\(of: #"\^\\d\{4\}-\\d\{2\}-\\d\{2\}\$"#', (ROOT / "ios/XiangshangYouth/Core/Models/GrowthInsight.swift").read_text(), "iOS strict growth date shape gate"),
        (r'private fun parseBusinessDate\(raw: String\)', (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/GrowthInsight.kt").read_text(), "Android strict growth date parser"),
        (r'Regex\("\^\\\\d\{4\}-\\\\d\{2\}-\\\\d\{2\}\$"\)', (ROOT / "android/app/src/main/java/com/xiangshang/youth/core/model/GrowthInsight.kt").read_text(), "Android strict growth date shape gate"),
        (r'static let reviewConfidenceThreshold = 0\.80', IOS_SCORE, "iOS review threshold"),
        (r'const val reviewConfidenceThreshold = \.80', ANDROID_SCORE, "Android review threshold"),
        (r'reviewConfidenceThreshold: 0\.8', BACKEND_SCORE, "backend review threshold"),
        (r'case 133\.\.\.180:', IOS_BODY, "iOS posture 12-15 boundary"),
        (r'minMonths = 133,\s*\n\s*maxMonths = 180', ANDROID_BODY, "Android posture 12-15 boundary"),
        (r'case 133\.\.\.168:', IOS_FOLLOW, "iOS follow-along 11-14 boundary"),
        (r'ageMonths in 133\.\.168', ANDROID_FOLLOW, "Android follow-along 11-14 boundary"),
        (r'ageMonths in 169\.\.216', ANDROID_FOLLOW, "Android follow-along 14-18 boundary"),
    ]
    for pattern, source, label in checks:
        require(pattern, source, label)

    # The four body-capture profiles are duplicated intentionally for native
    # runtime use; verify the first/last boundaries and the key quality gates.
    for source, label in ((IOS_BODY, "iOS"), (ANDROID_BODY, "Android")):
        require(r"6-8岁", source, f"{label} child capture profile")
        require(r"9-11岁", source, f"{label} junior capture profile")
        require(r"12-15岁", source, f"{label} adolescent capture profile")
        require(r"16-18岁", source, f"{label} teen capture profile")
        require(r"minimum.*Landmark.*Confidence|minimumIndividualLandmarkConfidence", source, f"{label} landmark gate")

    expected_assets = (
        (BODY_CAPTURE_ASSET, "body capture", [(72, 96), (97, 132), (133, 180), (181, 216)]),
        (FOLLOW_ACTION_ASSET, "follow-along", [(72, 96), (97, 132), (133, 168), (169, 216)])
    )
    for payload, label, expected_bands in expected_assets:
        bands = [(int(item["minAgeMonths"]), int(item["maxAgeMonths"])) for item in payload.get("ageProfiles", [])]
        if bands != expected_bands:
            raise AssertionError(f"{label} age bands drifted: {bands}")
        if any(start < 72 or end > 216 or start > end for start, end in bands):
            raise AssertionError(f"{label} age band outside supported 72..216 months")

    action_profiles = FOLLOW_ACTION_ASSET.get("actionProfiles", [])
    expected_action_categories = {
        "burpee", "front_raise", "high_knee", "jump_rope", "jumping_jack",
        "lateral_raise", "lunge", "plank", "sit_up", "squat", "squat_challenge"
    }
    if len(action_profiles) != 44 or {item.get("category") for item in action_profiles} != expected_action_categories:
        raise AssertionError("follow-along action profile asset must contain exactly 44 entries across 11 categories")
    action_keys = {(item.get("category"), int(item.get("minAgeMonths")), int(item.get("maxAgeMonths"))) for item in action_profiles}
    if len(action_keys) != len(action_profiles):
        raise AssertionError("follow-along action profile asset contains duplicate category/age keys")
    follow_bands = {(72, 96), (97, 132), (133, 168), (169, 216)}
    if any((int(item["minAgeMonths"]), int(item["maxAgeMonths"])) not in follow_bands for item in action_profiles):
        raise AssertionError("follow-along action profile age band outside canonical matrix")
    if any(int(item["minAgeMonths"]) < 72 or int(item["maxAgeMonths"]) > 216 for item in action_profiles):
        raise AssertionError("follow-along action profile outside supported 72..216 months")
    if MODEL_CORPUS.get("version") != "UY-IMCA-CV-1.3" or not MODEL_CORPUS.get("movement") or not MODEL_CORPUS.get("body") or not MODEL_CORPUS.get("followAlong"):
        raise AssertionError("golden model corpus missing or versioned differently")
    body_ages = {int(sample.get("ageMonths")) for sample in MODEL_CORPUS.get("body", []) if sample.get("ageMonths") is not None}
    body_genders = {str(sample.get("gender")) for sample in MODEL_CORPUS.get("body", [])}
    if not {72, 108, 156, 192}.issubset(body_ages) or not {"男", "女"}.issubset(body_genders):
        raise AssertionError("golden body corpus must cover four age anchors and both genders")
    if not all("expectedBmi" in sample and "expectedPosture" in sample for sample in MODEL_CORPUS.get("body", [])):
        raise AssertionError("golden body corpus must carry BMI and posture expected labels")
    if MODEL_SCHEMA.get("properties", {}).get("evidenceLevel", {}).get("const") != "human-labeled":
        raise AssertionError("labeled corpus schema must require human-labeled evidence")
    if MODEL_FITTER_SCHEMA.get("properties", {}).get("kind", {}).get("const") != "human-labeled-calibration":
        raise AssertionError("calibration corpus schema must require human-labeled-calibration")

    # BMI thresholds are duplicated for offline native use and the server
    # scorer. Compare every half-year row, not just a few boundary samples.
    for gender in ("boys", "girls"):
        ios_rows = extract_bmi_table(IOS_BODY, gender)
        android_rows = extract_bmi_table(ANDROID_BODY, gender, android=True)
        backend_rows = extract_bmi_table(BACKEND_BODY, gender, backend=True)
        if ios_rows != android_rows or ios_rows != backend_rows:
            raise AssertionError(f"BMI table drifted across platforms: {gender}")

    # Posture screening has four age-specific profiles. Compare every
    # threshold and weight across the API and both native clients, not merely
    # the public algorithm version string.
    posture_profiles = {
        "backend": extract_posture_profiles(BACKEND_POSTURE, "backend"),
        "iOS": extract_posture_profiles(IOS_BODY, "ios"),
        "Android": extract_posture_profiles(ANDROID_BODY, "android"),
    }
    expected_posture_bands = [(72, 96), (97, 132), (133, 180), (181, 216)]
    posture_fields = {
        "shoulderAttention", "shoulderReferral", "pelvisAttention", "pelvisReferral",
        "seatedMidlineAttention", "seatedRoundingAttention", "forwardHeadAttention",
        "forwardHeadReferral", "proxyAtrAttention", "proxyAtrReferral",
        "ribProminenceEquivocalCentimeters", "ribProminencePositiveCentimeters",
        "gaitAttention", "weightedShoulder", "weightedPelvis", "weightedSpinalMidline",
        "weightedThoracicRounding", "weightedForwardHead", "weightedAdams", "weightedGait",
        "yellowScore", "redScore",
    }
    for platform, profiles in posture_profiles.items():
        if [band for band, _ in profiles] != expected_posture_bands:
            raise AssertionError(f"posture age bands drifted: {platform}")
        if any(not posture_fields.issubset(values) for _, values in profiles):
            raise AssertionError(f"posture profile fields missing: {platform}")
    reference_profiles = posture_profiles["backend"]
    for platform in ("iOS", "Android"):
        for index, ((reference_band, reference), (actual_band, actual)) in enumerate(zip(reference_profiles, posture_profiles[platform])):
            if reference_band != actual_band:
                raise AssertionError(f"posture age band drifted at {platform}[{index}]")
            for field in posture_fields:
                if abs(reference[field] - actual[field]) > 1e-9:
                    raise AssertionError(f"posture profile drifted: {platform}[{index}] {field}")

    # Height reference rows are also duplicated in all three runtimes. A
    # single changed SD boundary can change a family-facing growth label, so
    # compare every age/sex row rather than relying on one example assertion.
    for gender in ("boys", "girls"):
        height_tables = {
            "backend": extract_height_table(BACKEND_BODY, gender, "backend"),
            "iOS": extract_height_table(IOS_BODY, gender, "ios"),
            "Android": extract_height_table(ANDROID_BODY, gender, "android"),
        }
        reference_rows = height_tables["backend"]
        for platform in ("iOS", "Android"):
            if height_tables[platform] != reference_rows:
                raise AssertionError(f"height table drifted across platforms: {gender}/{platform}")

    print(f"model contract OK ({len(checks) + 10} cross-platform invariants)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError) as error:
        print(f"model contract FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
