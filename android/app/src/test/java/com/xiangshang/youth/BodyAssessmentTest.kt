package com.xiangshang.youth

import com.xiangshang.youth.core.model.BodyAssessmentRecord
import com.xiangshang.youth.core.model.BodyAttentionLevel
import com.xiangshang.youth.core.model.BodyAssessmentDraft
import com.xiangshang.youth.core.model.BodyCaptureTask
import com.xiangshang.youth.core.model.BodyCaptureQualityGate
import com.xiangshang.youth.core.model.BodyMeasurementInput
import com.xiangshang.youth.core.model.HeightDevelopmentLevel
import com.xiangshang.youth.core.model.TestItem
import com.xiangshang.youth.core.model.PostureAssessmentReport
import com.xiangshang.youth.core.model.PostureMetricSnapshot
import com.xiangshang.youth.core.model.PostureMetricCalculator
import com.xiangshang.youth.core.model.PostureCaptureRepeatability
import com.xiangshang.youth.core.model.CaptureCalibrationEvidence
import com.xiangshang.youth.core.model.CaptureCalibrationMode
import com.xiangshang.youth.core.model.PostureScreeningRules
import com.xiangshang.youth.core.model.AssessmentScoreRules
import com.xiangshang.youth.core.model.GrowthInsight
import com.xiangshang.youth.core.model.GrowthReportPeriod
import com.xiangshang.youth.core.model.bodyAssessmentAgeMonths
import com.xiangshang.youth.core.model.ageMonthsFromBirthDate
import com.xiangshang.youth.core.model.gaitProgress
import com.xiangshang.youth.core.model.adamsForwardBendCompletionScore
import com.xiangshang.youth.core.model.hasAdamsLowerBodyPosition
import com.xiangshang.youth.core.model.hasReliableLandmarks
import com.xiangshang.youth.core.model.jointAngle
import com.xiangshang.youth.core.model.range
import com.xiangshang.youth.core.model.repeatability
import com.xiangshang.youth.core.model.robustRange
import com.xiangshang.youth.core.model.staticProgress
import com.xiangshang.youth.core.service.LocalFeatureState
import com.xiangshang.youth.core.service.LocalFeatureStore
import com.xiangshang.youth.feature.parent.CaptureBodyAlignment
import com.xiangshang.youth.feature.parent.CaptureCalibrationRules
import com.xiangshang.youth.core.model.SpineScreeningStandard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class BodyAssessmentTest {
    @Test
    fun footCloseUpUsesLowerLegScaleInsteadOfFullBodyScale() {
        assertEquals(BodyCaptureQualityGate.BodyScaleState.TooFar, BodyCaptureQualityGate.footScaleState(.18))
        assertEquals(BodyCaptureQualityGate.BodyScaleState.Ready, BodyCaptureQualityGate.footScaleState(.45))
        assertEquals(BodyCaptureQualityGate.BodyScaleState.TooClose, BodyCaptureQualityGate.footScaleState(.82))
        assertEquals(BodyCaptureQualityGate.BodyScaleState.Invalid, BodyCaptureQualityGate.footScaleState(Double.NaN))
    }

    @Test
    fun markerPnpEvidenceRequiresApprovedProfileId() {
        val evidence = CaptureCalibrationEvidence(
            mode = CaptureCalibrationMode.MarkerPnp, boardDetected = true, boardId = "uy-charuco-v1",
            intrinsicsId = "pixel-rear1x-v1", lensId = "rear-1x", resolution = "1920x1080",
            reprojectionErrorPx = 1.2, profileId = "pixel-rear1x-v1"
        )
        assertTrue(evidence.hasMarkerPnPEvidence)
        assertEquals(false, evidence.copy(profileId = null).hasMarkerPnPEvidence)
    }

    @Test
    fun postureCaptureRequiresTwoConsistentIndependentTakes() {
        fun snapshot(id: String, shoulder: Double, headTilt: Double) = PostureMetricSnapshot(
            id = id,
            task = BodyCaptureTask.ForwardBend,
            sampleCount = 24,
            confidence = .86,
            shoulderHeightDifferenceCm = shoulder,
            pelvicHeightDifferenceCm = .2,
            headTiltDegrees = headTilt,
            spinalMidlineDeviationCm = .3,
            thoracicRoundingDegrees = 12.0,
            forwardHeadAngleDegrees = 6.0
        )
        val first = snapshot("first", .30, 1.0)
        val second = snapshot("second", .85, 3.5)
        val stable = PostureCaptureRepeatability.verify(first, second)
        assertTrue(stable.passed)
        assertTrue(stable.comparedMetricCount >= 3)
        val merged = PostureCaptureRepeatability.merged(first, second, stable)
        assertEquals(.575, merged.shoulderHeightDifferenceCm ?: 0.0, .0001)
        assertEquals(48, merged.sampleCount)
        assertEquals("passed", merged.repeatabilityStatus)

        val unstable = PostureCaptureRepeatability.verify(snapshot("first", .30, 1.0), snapshot("third", 1.25, 4.5))
        assertEquals(false, unstable.passed)
        assertTrue(unstable.maximumDifference > .8)
    }

    @Test
    fun captureCalibrationRequiresLevelPhoneAndEveryBodyAnchor() {
        val level = CaptureCalibrationRules.deviceAlignment(0.0, 9.81, 0.0)
        assertTrue(level.available)
        assertTrue(level.isLevel)
        assertEquals(false, CaptureCalibrationRules.deviceAlignment(1.8, 9.6, 0.0).isLevel)
        assertEquals(false, CaptureCalibrationRules.deviceAlignment(0.0, 9.5, 2.4).isLevel)
        assertEquals(false, CaptureCalibrationRules.deviceAlignment(Double.NaN, 9.81, 0.0).available)

        val ready = CaptureBodyAlignment(
            bodyDetected = true,
            distanceState = BodyCaptureQualityGate.BodyScaleState.Ready,
            centered = true,
            headReady = true,
            shouldersReady = true,
            hipsReady = true,
            kneesReady = true,
            feetReady = true
        )
        assertTrue(ready.isReady)
        assertEquals(false, ready.copy(feetReady = false).isReady)
        assertEquals(false, ready.copy(distanceState = BodyCaptureQualityGate.BodyScaleState.TooClose).isReady)
        assertEquals(listOf(1, 2, 3, 4, 5), SpineScreeningStandard.items.map { it.number })
        assertEquals(8, SpineScreeningStandard.homeCameraItems.size)
        assertEquals(
            listOf(BodyCaptureTask.StandingFront, BodyCaptureTask.StandingBack, BodyCaptureTask.StandingSide, BodyCaptureTask.ForwardBend, BodyCaptureTask.DynamicKneeControl, BodyCaptureTask.GaitVideo, BodyCaptureTask.Seated, BodyCaptureTask.FootArch),
            SpineScreeningStandard.homeCameraItems.map { it.task }
        )
        assertEquals("亚当斯前屈试验", SpineScreeningStandard.items[1].title)
        assertTrue(SpineScreeningStandard.items[1].instruction.contains("膝关节完全伸直"))
        assertTrue(SpineScreeningStandard.items[1].instruction.contains("不屈膝、不弓步"))
        assertTrue(BodyCaptureQualityGate.hasAdamsLowerBodyPosition(listOf(172.0, 169.0), .045, .20, true))
        assertEquals(false, BodyCaptureQualityGate.hasAdamsLowerBodyPosition(listOf(142.0, 171.0), .045, .20, true))
        assertEquals(false, BodyCaptureQualityGate.hasAdamsLowerBodyPosition(listOf(172.0, 171.0), .18, .20, true))
        assertEquals(false, BodyCaptureQualityGate.hasAdamsLowerBodyPosition(listOf(172.0, 171.0), .09, .20, true))
        assertEquals(SpineScreeningStandard.AtrBand.Green, SpineScreeningStandard.atrBand(4.9))
        assertEquals(SpineScreeningStandard.AtrBand.Yellow, SpineScreeningStandard.atrBand(5.0))
        assertEquals(SpineScreeningStandard.AtrBand.Yellow, SpineScreeningStandard.atrBand(6.9))
        assertEquals(SpineScreeningStandard.AtrBand.Red, SpineScreeningStandard.atrBand(7.0))
        assertEquals(1.8, SpineScreeningStandard.maximumOcciputWallDistance(1.4, 1.8))
        assertEquals(null, SpineScreeningStandard.maximumOcciputWallDistance(1.4, null))
    }

    @Test
    fun validMetricsAdvanceToEnvironmentCheckInNineStepFlow() {
        assertEquals(4, com.xiangshang.youth.feature.parent.bodyAssessmentStepAfterMetrics(true))
        assertEquals(3, com.xiangshang.youth.feature.parent.bodyAssessmentStepAfterMetrics(false))
    }

    @Test
    fun nineStepDraftRestoresResultAndPlanWithoutLegacyClamping() {
        val resultDraft = BodyAssessmentDraft(stage = 7, guardianReady = true, consentAcknowledged = true)
        val planDraft = BodyAssessmentDraft(stage = 8, guardianReady = true, consentAcknowledged = true)
        assertEquals(7, com.xiangshang.youth.feature.parent.initialBodyAssessmentStage(resultDraft, false, true))
        assertEquals(8, com.xiangshang.youth.feature.parent.initialBodyAssessmentStage(planDraft, false, true))
    }

    @Test
    fun outdatedConsentReturnsResumedDraftToConsentGate() {
        val cameraDraft = BodyAssessmentDraft(stage = 5, guardianReady = true, consentAcknowledged = true)
        assertEquals(1, com.xiangshang.youth.feature.parent.initialBodyAssessmentStage(cameraDraft, false, false))
    }
    private fun resolveBodyCaptureProfileJson(): String {
        val workingDirectory = File(requireNotNull(System.getProperty("user.dir")))
        val candidates = listOf(
            workingDirectory.resolve("src/main/assets/body_pose_capture_profiles.json"),
            workingDirectory.resolve("app/src/main/assets/body_pose_capture_profiles.json"),
            workingDirectory.resolve("android/app/src/main/assets/body_pose_capture_profiles.json")
        )
        return requireNotNull(candidates.firstOrNull { it.exists() }) { "body_pose_capture_profiles.json not found" }.readText()
    }

    @Test
    fun bundledVersionedPostureAssetLoadsAsOneCanonicalMatrix() {
        assertEquals(true, BodyCaptureQualityGate.setProfileOverridesFromJson(resolveBodyCaptureProfileJson()))
        assertEquals("6-8岁", BodyCaptureQualityGate.profileForAge(84).tag)
        assertEquals("16-18岁", BodyCaptureQualityGate.profileForAge(192).tag)
        BodyCaptureQualityGate.clearProfileOverrides()
    }

    @Test
    fun captureTaskApiCodesMatchTheCrossPlatformContract() {
        assertEquals(listOf("standingFront", "standingBack", "standingSide", "forwardBend", "dynamicKneeControl", "seatedPosture", "gaitVideo", "footArch"), BodyCaptureTask.values().map { it.apiCode })
    }

    @Test
    fun rollCorrectionRemovesPhoneTiltFromLevelShoulderLine() {
        val angle = Math.PI / 6.0
        val dx = kotlin.math.cos(angle)
        val dy = kotlin.math.sin(angle)
        // Both landmarks lie on the camera-roll axis, so their corrected
        // vertical difference must be zero even though raw Y differs.
        val corrected = PostureMetricCalculator.rollCorrectedVerticalDifference(
            firstX = 0.0,
            firstY = 0.0,
            secondX = dx,
            secondY = dy,
            axisDx = dx,
            axisDy = dy
        )
        assertEquals(0.0, corrected, 0.000001)
        assertEquals(false, BodyCaptureQualityGate.forwardBendReady(2500, 20, .01, Double.POSITIVE_INFINITY, 120))
        assertEquals(false, BodyCaptureQualityGate.forwardBendReady(2500, 20, .01, -.2, null))
        assertEquals(false, BodyCaptureQualityGate.forwardBendReady(2500, 20, .01, 10.1, null))
    }

    @Test
    fun postureSamplingRejectsOutliersAndEvaluatesTenRunRepeatability() {
        assertEquals(10.0, PostureMetricCalculator.robustMedian(listOf(10.0, 10.1, 9.9, 10.0, 60.0))!!, .001)
        assertEquals(.07, PostureMetricCalculator.robustRange(listOf(.10, .11, .12, .13, .14, .15, .16, .17, .18, 5.0))!!, .001)
        assertEquals(true, PostureMetricCalculator.isStableSeries(List(18) { .20 }, 18, .55))
        assertEquals(false, PostureMetricCalculator.isStableSeries(List(17) { .20 }, 18, .55))

        val stableRuns = listOf(1.00, 1.04, .98, 1.02, 1.01, .99, 1.05, .97, 1.03, 1.00)
        assertEquals(true, PostureMetricCalculator.repeatability(stableRuns, maximumRange = .20, maximumStandardDeviation = .08).passed)
        assertEquals(false, PostureMetricCalculator.repeatability(stableRuns.take(9), maximumRange = .20, maximumStandardDeviation = .08).passed)
        assertEquals(false, PostureMetricCalculator.repeatability(listOf(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.8), maximumRange = .20, maximumStandardDeviation = .08).passed)
    }

    @Test
    fun bmiLevelUsesPublishedHalfYearAgeBuckets() {
        val boy = BodyAssessmentRecord(100.0, 16.9, "2026-08-11", emptySet(), false, false, "2026-08-11")
        // 75个月使用已完成的72个月档位；标准不定义逐月插值阈值。
        assertEquals(BodyAttentionLevel.Yellow, boy.bmiLevel(75, "男"))
        assertEquals(BodyAttentionLevel.Yellow, BodyAssessmentRecord(100.0, 16.5, "2026-08-11", emptySet(), false, false, "2026-08-11").bmiLevel(75, "男"))
        assertEquals(BodyAttentionLevel.Red, BodyAssessmentRecord(100.0, 18.0, "2026-08-11", emptySet(), false, false, "2026-08-11").bmiLevel(75, "男"))
        assertEquals(BodyAttentionLevel.Yellow, boy.bmiLevel(75, "male"))
        assertEquals(BodyAttentionLevel.Yellow, boy.bmiLevel(75, "F"))
    }

    @Test
    fun postureReportWithNoMetricWillStillExplainUnexplainableState() {
        val sampleMap = emptyMap<BodyCaptureTask, PostureMetricSnapshot>()
        val report = PostureAssessmentReport.make(sampleMap, "2026-08-11", 120)
        assertEquals(BodyAttentionLevel.Pending, report.overallLevel)
        assertTrue(report.reasons.isNotEmpty())
        assertTrue(report.reasons.first().contains("人工标注验证"))
        assertEquals(com.xiangshang.youth.core.model.AlgorithmValidationStatus.PendingHumanValidation, report.validationStatus)
        assertEquals(false, report.canPublishClassification)
        assertEquals(0, report.riskScore)
        assertEquals(PostureAssessmentReport.calibrationVersion, report.calibrationVersion)
        assertEquals(PostureScreeningRules.rulesSourceVersion, report.rulesSourceVersion)
        assertEquals("UY-MODELS-1.1", AssessmentScoreRules.modelRegistryVersion)
        assertEquals("UY-IMCA-SCORE-1.3", AssessmentScoreRules.algorithmVersion)
        assertEquals("UY-IMCA-BMI-1.2", BodyAssessmentRecord.bmiAlgorithmVersion)
        assertEquals("UY-IMCA-HEIGHT-1.0", BodyAssessmentRecord.heightAlgorithmVersion)
    }

    @Test
    fun movementAggregateUsesCanonicalHalfUpRounding() {
        assertEquals(21.0, AssessmentScoreRules.total(20.95), 0.0001)
        assertEquals(0.0, AssessmentScoreRules.total(Double.NaN), 0.0001)
        assertEquals(AssessmentScoreRules.totalMaximum, AssessmentScoreRules.total(99.0), 0.0001)
    }

    @Test
    fun bmiUsesOfficialHalfYearScreeningThresholds() {
        val obese = BodyAssessmentRecord(100.0, 18.7, "2026-08-11", emptySet(), false, false, "2026-08-11")
        val overweight = BodyAssessmentRecord(100.0, 17.0, "2026-08-11", emptySet(), false, false, "2026-08-11")

        // Boy aged 7.0 (84 months): WS/T 586—2018 threshold is 17.0 / 18.7.
        assertEquals(BodyAttentionLevel.Red, obese.bmiLevel(84, "男"))
        assertEquals(BodyAttentionLevel.Yellow, overweight.bmiLevel(84, "男"))
        assertEquals(BodyAttentionLevel.Unavailable, overweight.bmiLevel(null, "男"))
        assertEquals("超重筛查关注", overweight.bmiScreeningLabel(84, "男"))
        assertEquals("建议关注", overweight.level(84, "男").label)
        assertEquals(BodyAttentionLevel.Unavailable, overweight.bmiLevel(217, "男"))
    }

    @Test
    fun bmiRoundsToOneDecimalAndRejectsMissingSex() {
        val edge = BodyAssessmentRecord(100.0, 16.96, "2026-08-11", emptySet(), false, false, "2026-08-11")
        assertEquals(17.0, edge.bmiForScreening, 0.001)
        assertEquals(BodyAttentionLevel.Yellow, edge.bmiLevel(84, "男"))
        assertEquals(BodyAttentionLevel.Unavailable, edge.bmiLevel(84, ""))
        assertEquals("待完善出生日期", edge.bmiScreeningLabel(null, "男"))
        assertEquals("待完善性别", edge.bmiScreeningLabel(84, ""))
        assertEquals(0.0, BodyAssessmentRecord(40.0, 8.0, "2026-08-11", emptySet(), false, false, "2026-08-11").bmi, 0.001)
        assertEquals(null, BodyAssessmentRecord(40.0, 20.0, "2026-08-11", emptySet(), false, false, "2026-08-11").heightDevelopmentAssessment(108, "男"))
    }

    @Test
    fun historicalBodyAssessmentKeepsMeasurementAgeBand() {
        val record = BodyAssessmentRecord(100.0, 17.2, "2026-08-11", emptySet(), false, false, "2026-08-11", ageMonthsAtMeasurement = 84)
        assertEquals(BodyAttentionLevel.Yellow, record.bmiLevel(90, "男"))
        assertEquals("超重筛查关注", record.bmiScreeningLabel(90, "男"))
    }

    @Test
    fun birthDateParsingRejectsImpossibleAndFutureDates() {
        val invalid = com.xiangshang.youth.core.model.Student("invalid", "测试", "三年级", "三年级1班", "南湖区", false, com.xiangshang.youth.core.model.TaskStatus.Completed, null, "男", "2026-02-31")
        val future = invalid.copy(id = "future", birthDate = "2999-01-01")
        val suffix = invalid.copy(id = "suffix", birthDate = "2018-08-22junk")
        assertEquals(null, invalid.bodyAssessmentAgeMonths)
        assertEquals(null, future.bodyAssessmentAgeMonths)
        assertEquals(null, suffix.bodyAssessmentAgeMonths)
    }

    @Test
    fun birthDateAgeUsesChinaCalendarAtMidnightBoundary() {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSX", Locale.US)
        val beforeMidnight = formatter.parse("2026-08-22T15:59:00.000Z")!!
        val afterMidnight = formatter.parse("2026-08-22T16:00:00.000Z")!!
        assertEquals(96, ageMonthsFromBirthDate("2018-08-22", beforeMidnight))
        assertEquals(95, ageMonthsFromBirthDate("2018-08-23", beforeMidnight))
        assertEquals(96, ageMonthsFromBirthDate("2018-08-23", afterMidnight))
    }

    @Test
    fun inProgressAssessmentDraftKeepsOnlyStructuredData() {
        val draft = BodyAssessmentDraft(
            stage = 2,
            heightCm = 133.5,
            weightKg = 31.2,
            captures = setOf(BodyCaptureTask.StandingBack, BodyCaptureTask.Seated),
            visualObservationHint = "请由家长确认画面对齐提示。",
            captureObservationHints = mapOf(BodyCaptureTask.StandingBack.name to "站姿提示", BodyCaptureTask.Seated.name to "坐姿提示")
        )
        val local = LocalFeatureState(bodyAssessmentDrafts = mapOf("s01" to draft))

        assertEquals(draft, local.bodyAssessmentDrafts["s01"])
        assertEquals(2, local.bodyAssessmentDrafts["s01"]?.captures?.size)
        assertEquals("站姿提示", local.bodyAssessmentDrafts["s01"]?.captureObservationHints?.get(BodyCaptureTask.StandingBack.name))
    }

    @Test
    fun supervisedSpineDraftRestoresEveryManualStandardField() {
        val restored = LocalFeatureStore.decodeBodyAssessmentDrafts(
            """{"s01":{"stage":5,"height":133.5,"weight":31.2,"captures":["StandingBack"],"standingShoulder":0.4,"standingPelvis":0.3,"standingHeadTilt":2.5,"adamsObservedResult":"equivocal","adamsProminenceSide":"右","gaitObservedAbnormal":true,"gaitObservationNote":"右侧骨盆摆动不对称","seatedMidline":0.6,"seatedShoulder":0.4,"seatedThoracicKyphosisObserved":false,"thoracicAtr":5.2,"lumbarAtr":3.4,"thoracicAtrSide":"右","lumbarAtrSide":"左","atrRetestEnabled":true,"thoracicAtrRepeat":5.4,"lumbarAtrRepeat":3.2,"seatedForwardBendAtr":2.0,"occiputWallDistanceFirst":1.4,"occiputWallDistanceSecond":1.6,"occiputWallDistance":1.6}}"""
        )["s01"]!!

        assertEquals("equivocal", restored.adamsObservedResult)
        assertEquals("右", restored.adamsProminenceSide)
        assertEquals(5.4, restored.thoracicAtrRepeatDegrees!!, .001)
        assertEquals(1.6, restored.occiputWallDistanceCm!!, .001)
        assertEquals("右侧骨盆摆动不对称", restored.gaitObservationNote)
        assertEquals(true, SpineScreeningStandard.isApplicable(72))
        assertEquals(true, SpineScreeningStandard.isApplicable(155))
        assertEquals(false, SpineScreeningStandard.isApplicable(156))
    }

    @Test
    fun bmiAndGeneticHeightUseProvidedFormula() {
        val record = BodyAssessmentRecord(150.0, 45.0, "2026-08-11", emptySet(), false, false, "2026-08-11", fatherHeightCm = 178.0, motherHeightCm = 162.0)

        assertEquals(20.0, record.bmi, 0.001)
        assertEquals(176.5, record.geneticHeightReference("男")!!, 0.001)
        assertEquals(163.5, record.geneticHeightReference("女")!!, 0.001)
        assertEquals(171.5, record.geneticHeightRange("男")!!.start, 0.001)
        assertEquals(181.5, record.geneticHeightRange("男")!!.endInclusive, 0.001)
        assertEquals(176.5, record.geneticHeightReference("male")!!, 0.001)
        assertEquals(null, record.geneticHeightReference(""))
        assertEquals("待完善孩子性别后计算", record.geneticHeightFormula(""))
        val invalidParents = record.copy(fatherHeightCm = 90.0)
        assertEquals(null, invalidParents.geneticHeightReference("男"))
    }

    @Test
    fun heightDevelopmentUsesWS612AgeSexBands() {
        val middle = BodyAssessmentRecord(135.81, 30.0, "2026-08-11", emptySet(), false, false, "2026-08-11")
        assertEquals(HeightDevelopmentLevel.Middle, middle.heightDevelopmentAssessment(108, "男")?.level)
        assertEquals(135.81, middle.heightDevelopmentAssessment(108, "男")?.median ?: 0.0, 0.001)
        assertEquals(null, middle.heightDevelopmentAssessment(83, "男"))
        assertEquals(null, middle.heightDevelopmentAssessment(108, ""))
    }

    @Test
    fun assessmentScoringClampsPartialAndLowConfidenceResults() {
        val student = com.xiangshang.youth.core.model.Student("score-test", "测试", "三年级", "三年级1班", "南湖区", false, com.xiangshang.youth.core.model.TaskStatus.Completed, null, "男")
        val partial = com.xiangshang.youth.core.model.DiagnosisReport("r1", student, "2026-09-12", listOf(
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 6.0, "", 1.2, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed),
            com.xiangshang.youth.core.model.ScoreResult(TestItem.LateralStep, -1.0, "", -.2, com.xiangshang.youth.core.model.ScoreReviewStatus.PendingReview)
        ), emptyList(), emptyList(), emptyList(), emptyList(), "v1", com.xiangshang.youth.core.model.RegionPolicy("p", "南湖区"))
        assertEquals(5.0, partial.totalScore, .001)
        assertEquals(2.0 / 7.0, partial.scoreCompletionRatio, .001)
        assertEquals(com.xiangshang.youth.core.model.AssessmentRiskLevel.Unavailable, partial.riskLevel)
        assertEquals(true, partial.requiresReview)
        val conflicting = partial.copy(scores = listOf(
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 1.0, "", .95, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed),
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 4.0, "", .95, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed)
        ))
        assertEquals(listOf(TestItem.ObstacleJump), conflicting.conflictingItems)
        assertEquals(true, conflicting.requiresReview)
        val duplicate = partial.copy(scores = listOf(
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 1.0, "", .4, com.xiangshang.youth.core.model.ScoreReviewStatus.PendingReview),
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 4.0, "", .95, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed)
        ))
        assertEquals(1, duplicate.normalizedScores.size)
        assertEquals(4.0, duplicate.totalScore, .001)

        val lowConfidenceMarkedPassed = partial.copy(scores = listOf(
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 4.0, "", .6, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed)
        ))
        assertEquals(com.xiangshang.youth.core.model.ScoreReviewStatus.PendingReview, lowConfidenceMarkedPassed.normalizedScores.first().reviewStatus)
        assertEquals(true, lowConfidenceMarkedPassed.requiresReview)

        val completeButPendingReview = partial.copy(id = "r-complete-pending", scores = TestItem.entries.map { item ->
            com.xiangshang.youth.core.model.ScoreResult(item, 4.0, "", .6, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed)
        })
        assertEquals(com.xiangshang.youth.core.model.AssessmentRiskLevel.Unavailable, completeButPendingReview.riskLevel)
        assertEquals(true, completeButPendingReview.requiresReview)
        val reviewedButStillPending = partial.copy(id = "r-reviewed-pending", scores = TestItem.entries.map { item ->
            com.xiangshang.youth.core.model.ScoreResult(item, 4.0, "已查看证据但未批准", .95, com.xiangshang.youth.core.model.ScoreReviewStatus.PendingReview, humanReviewed = true)
        })
        assertEquals(com.xiangshang.youth.core.model.AssessmentRiskLevel.Unavailable, reviewedButStillPending.riskLevel)
        assertEquals(true, reviewedButStillPending.requiresReview)
        val humanApproved = partial.copy(id = "r-human-approved", scores = TestItem.entries.map { item ->
            com.xiangshang.youth.core.model.ScoreResult(item, 4.0, "人工核验", .6, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed, humanReviewed = true)
        })
        assertEquals(com.xiangshang.youth.core.model.AssessmentRiskLevel.Low, humanApproved.riskLevel)
        assertEquals(false, humanApproved.requiresReview)

        val tied = partial.copy(scores = listOf(
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 1.0, "", .9, com.xiangshang.youth.core.model.ScoreReviewStatus.PendingReview),
            com.xiangshang.youth.core.model.ScoreResult(TestItem.ObstacleJump, 4.0, "", .9, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed)
        ))
        assertEquals(com.xiangshang.youth.core.model.ScoreReviewStatus.Passed, tied.normalizedScores.first().reviewStatus)

        val completeScores = TestItem.entries.mapIndexed { index, item -> com.xiangshang.youth.core.model.ScoreResult(item, if (index == 0) 2.5 else 3.5, "", .95, com.xiangshang.youth.core.model.ScoreReviewStatus.Passed) }
        val complete = partial.copy(id = "r2", scores = completeScores)
        assertEquals(com.xiangshang.youth.core.model.AssessmentRiskLevel.Attention, complete.riskLevel)
        assertEquals(true, complete.requiresFollowUp)
    }

    @Test
    fun classCompletionUsesStudentCountWeighting() {
        val classes = listOf(
            com.xiangshang.youth.core.model.ClassInfo("small", "小班", "g", "", 1, 100),
            com.xiangshang.youth.core.model.ClassInfo("large", "大班", "g", "", 9, 0)
        )
        val total = classes.sumOf { it.studentCount }
        val completed = classes.sumOf { it.completedStudentEstimate }
        assertEquals(10, total)
        assertEquals(1, completed)
        assertEquals(.1, completed.toDouble() / total, .001)
    }

    @Test
    fun emptyMeasurementsAreNotClassifiedAsHealthy() {
        val empty = BodyAssessmentRecord(0.0, 0.0, "2026-08-11", emptySet(), false, false, "2026-08-11")

        assertEquals(0.0, empty.bmi, 0.001)
        assertEquals(BodyAttentionLevel.Unavailable, empty.bmiLevel(108, "男"))
        assertEquals("待填写身高体重", empty.bmiScreeningLabel(108, "男"))
    }

    @Test
    fun malformedInfiniteMeasurementsFailSafeToUnavailable() {
        val malformed = BodyAssessmentRecord(Double.POSITIVE_INFINITY, 45.0, "2026-08-11", emptySet(), false, false, "2026-08-11")
        assertEquals(0.0, malformed.bmi, 0.001)
        assertEquals(BodyAttentionLevel.Unavailable, malformed.bmiLevel(120, "女"))
        assertEquals(null, malformed.heightDevelopmentAssessment(120, "女"))
    }

    @Test
    fun incompleteVisualCaptureIsNotPublishedAsAHealthRisk() {
        val record = BodyAssessmentRecord(130.0, 27.0, "2026-08-11", emptySet(), false, false, "2026-08-11")
        assertEquals(BodyAttentionLevel.Pending, record.postureLevel())
        assertEquals(BodyAttentionLevel.Pending, record.level(108, "男"))
        assertEquals(false, record.level(108, "男") == BodyAttentionLevel.Yellow)

        val now = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse("2026-08-11")!!
        val insight = GrowthInsight.make(GrowthReportPeriod.Week, emptySet(), emptySet(), 0, BodyAttentionLevel.Pending, null, now)
        assertEquals("完成家庭观察计划", insight.planTitle)
        assertEquals(true, insight.planReason.contains("不将未完成记录当作健康风险"))
        val sanitized = GrowthInsight.make(GrowthReportPeriod.Week, emptySet(), emptySet(), -4, null, Double.NaN, now)
        assertEquals(0, sanitized.assessmentCount)
        assertEquals("轻量习惯计划", sanitized.planTitle)
    }

    @Test
    fun measurementInputNormalizesRangeAndPrecision() {
        assertEquals(133.5, BodyMeasurementInput.normalized(133.26, 90.0..190.0, .5), .001)
        assertEquals(31.2, BodyMeasurementInput.normalized(31.24, 15.0..90.0, .1), .001)
        assertEquals(1.0, BodyMeasurementInput.normalized(1.0, 1.0..2.0, 0.0), .001)
        assertEquals(15.0, BodyMeasurementInput.normalized(-10.0, 15.0..90.0, .1), .001)
        assertEquals(220.0, BodyMeasurementInput.normalized(280.0, 130.0..220.0, .5), .001)
        assertEquals(90.0, BodyMeasurementInput.normalized(Double.POSITIVE_INFINITY, 90.0..190.0, .5), .001)
    }

    @Test
    fun visualCaptureGateRequiresStablePoseAndRealGaitMovement() {
        assertEquals(false, BodyCaptureQualityGate.staticReady(2400, 20, .01))
        assertEquals(false, BodyCaptureQualityGate.staticReady(2500, 20, .04))
        assertEquals(true, BodyCaptureQualityGate.staticReady(2500, 20, .02))
        assertEquals(false, BodyCaptureQualityGate.staticReady(2500, 20, .02, .02))
        assertEquals(true, BodyCaptureQualityGate.staticReady(2500, 20, .02, .005))
        assertEquals(true, BodyCaptureQualityGate.gaitReady(6400, .04))
        assertEquals(true, BodyCaptureQualityGate.gaitReady(6400, .04, 7))
        assertEquals(false, BodyCaptureQualityGate.gaitReady(6400, .02))
        assertEquals(false, BodyCaptureQualityGate.forwardBendReady(2500, 20, .01, .10))
        assertEquals(true, BodyCaptureQualityGate.forwardBendReady(2500, 20, .01, .45))
        assertEquals(false, BodyCaptureQualityGate.hasUsableBodyScale(.30, false))
        assertEquals(true, BodyCaptureQualityGate.hasUsableBodyScale(.50, false))
        assertEquals(false, BodyCaptureQualityGate.hasUsableBodyScale(.82, false))
        assertEquals(BodyCaptureQualityGate.BodyScaleState.TooFar, BodyCaptureQualityGate.bodyScaleState(.30, false))
        assertEquals(BodyCaptureQualityGate.BodyScaleState.Ready, BodyCaptureQualityGate.bodyScaleState(.50, false))
        assertEquals(BodyCaptureQualityGate.BodyScaleState.TooClose, BodyCaptureQualityGate.bodyScaleState(.82, false))
        assertEquals(false, BodyCaptureQualityGate.hasUsableBodyScale(.12, true))
        assertEquals(false, BodyCaptureQualityGate.hasUsableBodyScale(.48, true))
        assertEquals(true, BodyCaptureQualityGate.hasComfortableFollowAlongFraming(.70, .30))
        assertEquals(false, BodyCaptureQualityGate.hasComfortableFollowAlongFraming(.82, .30))
        assertEquals(false, BodyCaptureQualityGate.hasComfortableFollowAlongFraming(.70, .40))
        assertEquals(true, BodyCaptureQualityGate.hasUsableSeatedGeometry(.65, .85, .20))
        assertEquals(false, BodyCaptureQualityGate.hasUsableSeatedGeometry(.85, .65, .20))
        assertEquals(true, BodyCaptureQualityGate.hasReliableLandmarks(listOf(.72f, .62f, .58f, .60f)))
        assertEquals(false, BodyCaptureQualityGate.hasReliableLandmarks(listOf(.96f, .96f, .33f, .34f)))
        assertEquals(false, BodyCaptureQualityGate.hasReliableLandmarks(listOf(.9f, .9f, .2f, .9f)))
        assertEquals(false, BodyCaptureQualityGate.hasReliableLandmarks(listOf(.9f, Float.POSITIVE_INFINITY, .9f, .9f)))
        assertEquals(true, BodyCaptureQualityGate.hasReliableForwardBendLandmarks(listOf(.82f, .76f, .74f, .78f, .73f), listOf(.72f, .10f), 120))
        assertEquals(false, BodyCaptureQualityGate.hasReliableForwardBendLandmarks(listOf(.82f, .76f, .74f, .78f, .73f), listOf(.12f, .10f), 120))
        assertEquals(.90, BodyCaptureQualityGate.adamsForwardBendCompletionScore(40.0, 52.0, 60.0, 52.0, 50.0) ?: 0.0, .001)
        assertEquals(0.0, BodyCaptureQualityGate.adamsForwardBendCompletionScore(40.0, 70.0, 60.0, 70.0, 50.0) ?: -1.0, .001)
        assertEquals(null, BodyCaptureQualityGate.adamsForwardBendCompletionScore(Double.POSITIVE_INFINITY, 52.0, 60.0, 52.0, 50.0))
        assertEquals(false, BodyCaptureQualityGate.hasUsableBodyScale(Double.POSITIVE_INFINITY, false))
        assertEquals(.96f, BodyCaptureQualityGate.staticProgress(10_000), .001f)
    }

    @Test
    fun visualCaptureGatesSupportAgeProfiles() {
        val profile6 = BodyCaptureQualityGate.profileForAge(80)
        val profile12 = BodyCaptureQualityGate.profileForAge(130)
        assertNotEquals(profile6.tag, profile12.tag)
        assertEquals(true, profile6.staticHoldMilliseconds > profile12.staticHoldMilliseconds)
        assertEquals(true, profile6.staticMaximumDisplacementRatio > profile12.staticMaximumDisplacementRatio)

        assertEquals(true, BodyCaptureQualityGate.staticReady(2600, 20, .028, 80))
        assertEquals(false, BodyCaptureQualityGate.staticReady(2500, 20, .028, 80))
        assertEquals(true, BodyCaptureQualityGate.staticReady(2500, 20, .028, 130))

        assertEquals(false, BodyCaptureQualityGate.gaitReady(6400, .034, 6, 80))
        assertEquals(true, BodyCaptureQualityGate.gaitReady(6600, .037, 7, 80))
        assertEquals(false, BodyCaptureQualityGate.gaitReady(6400, .034, 7, 130))
        assertEquals(true, BodyCaptureQualityGate.gaitReady(6400, .039, 7, 130))

        assertEquals(false, BodyCaptureQualityGate.forwardBendReady(1200, 12, .02, .2, 80))
        assertEquals(true, BodyCaptureQualityGate.forwardBendReady(2500, 20, .02, .36, 130))
        assertEquals(null, PostureMetricCalculator.centimeters(Double.POSITIVE_INFINITY, .4, 140.0))
        assertEquals(null, PostureMetricCalculator.centimeters(.02, Double.NaN, 140.0))
    }

    @Test
    fun visualCaptureProfileOverrideFallbackShouldIgnoreInvalidConfig() {
        val broken = """
            {"ageProfiles":[{"tag":"测试","minAgeMonths":72}]
            """.trimIndent()
        assertEquals(false, BodyCaptureQualityGate.setProfileOverridesFromJson(broken))
        val profile = BodyCaptureQualityGate.profileForAge(100)
        assertEquals("9-11岁", profile.tag)
        assertEquals(2500L, profile.staticHoldMilliseconds)
        val extreme = """
            {"ageProfiles":[{"tag":"异常","minAgeMonths":72,"maxAgeMonths":96,"staticHoldMilliseconds":-1,"minimumMeanLandmarkConfidence":9}]}
        """.trimIndent()
        assertEquals(false, BodyCaptureQualityGate.setProfileOverridesFromJson(extreme))
        assertEquals("9-11岁", BodyCaptureQualityGate.profileForAge(100).tag)
        assertEquals(.031, profile.staticMaximumDisplacementRatio, .0001)
        assertEquals(7, profile.gaitMovementWindowFrames)
    }

    @Test
    fun versionedPostureAssetMustContainAllCanonicalAgeBands() {
        val incomplete = """
            {"version":"android-v1-search-calibrated-2026-09-15","ageProfiles":[
              {"tag":"6-8岁","minAgeMonths":72,"maxAgeMonths":96}
            ]}
        """.trimIndent()
        assertEquals(false, BodyCaptureQualityGate.setProfileOverridesFromJson(incomplete))
        assertEquals("9-11岁", BodyCaptureQualityGate.profileForAge(100).tag)
    }

    @Test
    fun postureReportUsesObjectiveThresholdsAndIgnoresParentRiskCheckboxes() {
        fun snapshot(task: BodyCaptureTask, atr: Double = 2.0, shoulder: Double = .2) = PostureMetricSnapshot(
            id = task.name, task = task, sampleCount = 18, confidence = .82,
            shoulderHeightDifferenceCm = shoulder, pelvicHeightDifferenceCm = .2,
            spinalMidlineDeviationCm = .2, thoracicRoundingDegrees = 10.0,
            forwardHeadAngleDegrees = 5.0, cameraProxyAtrDegrees = atr,
            cameraProxyRibProminenceCm = .2
        )
        val greenSnapshots = BodyCaptureTask.values().associateWith { snapshot(it) }
        val greenReport = PostureAssessmentReport.makeValidatedFixture(greenSnapshots, "2026-08-11")
        assertEquals(BodyAttentionLevel.Pending, PostureAssessmentReport.makeValidatedFixture(greenSnapshots, "2026-08-11", 156).overallLevel)
        val productReport = PostureAssessmentReport.make(greenSnapshots, "2026-08-11")
        assertEquals(BodyAttentionLevel.Pending, productReport.overallLevel)
        assertEquals(0, productReport.riskScore)
        assertEquals(false, productReport.canPublishClassification)
        val green = BodyAssessmentRecord(150.0, 30.0, "2026-08-11", BodyCaptureTask.values().toSet(), true, true, "2026-08-11", postureReport = greenReport)
        assertEquals(BodyAttentionLevel.Green, greenReport.overallLevel)
        assertEquals(BodyAttentionLevel.Green, green.level(108, "男"))

        val redSnapshots = greenSnapshots.toMutableMap().apply {
            this[BodyCaptureTask.StandingBack] = snapshot(BodyCaptureTask.StandingBack, shoulder = 2.0)
        }
        assertEquals(BodyAttentionLevel.Yellow, PostureAssessmentReport.makeValidatedFixture(redSnapshots, "2026-08-11").overallLevel)
        val multiSignalSnapshots = redSnapshots.toMutableMap().apply {
            this[BodyCaptureTask.ForwardBend] = snapshot(BodyCaptureTask.ForwardBend, atr = 2.0, shoulder = .2).copy(cameraProxyRibProminenceCm = 1.3)
            this[BodyCaptureTask.GaitVideo] = snapshot(BodyCaptureTask.GaitVideo, atr = 2.0, shoulder = .2).copy(gaitTrunkSwayCm = 1.4)
        }
        assertEquals(BodyAttentionLevel.Red, PostureAssessmentReport.makeValidatedFixture(multiSignalSnapshots, "2026-08-11").overallLevel)
        val proxyOnlySnapshots = greenSnapshots.toMutableMap().apply {
            this[BodyCaptureTask.ForwardBend] = snapshot(BodyCaptureTask.ForwardBend, atr = 30.0)
        }
        assertEquals(BodyAttentionLevel.Green, PostureAssessmentReport.makeValidatedFixture(proxyOnlySnapshots, "2026-08-11").overallLevel)
        val instrumentAtrSnapshots = greenSnapshots.toMutableMap().apply {
            this[BodyCaptureTask.ForwardBend] = snapshot(BodyCaptureTask.ForwardBend, atr = 2.0).copy(cameraProxyRibProminenceCm = null, instrumentAtrDegrees = 7.0)
        }
        assertEquals(BodyAttentionLevel.Red, PostureAssessmentReport.makeValidatedFixture(instrumentAtrSnapshots, "2026-08-11").overallLevel)
        val functionalReview = greenSnapshots.toMutableMap().apply {
            this[BodyCaptureTask.ForwardBend] = snapshot(BodyCaptureTask.ForwardBend, atr = 2.0).copy(cameraProxyRibProminenceCm = null, thoracicAtrDegrees = 5.5, seatedForwardBendAtrDegrees = 1.5)
        }
        assertEquals(BodyAttentionLevel.Yellow, PostureAssessmentReport.makeValidatedFixture(functionalReview, "2026-08-11").overallLevel)
        val fixedReview = functionalReview.toMutableMap().apply {
            this[BodyCaptureTask.ForwardBend] = this[BodyCaptureTask.ForwardBend]!!.copy(seatedForwardBendAtrDegrees = 5.0)
        }
        assertEquals(BodyAttentionLevel.Red, PostureAssessmentReport.makeValidatedFixture(fixedReview, "2026-08-11").overallLevel)
        val malformed = greenSnapshots.toMutableMap().apply {
            this[BodyCaptureTask.StandingBack] = snapshot(BodyCaptureTask.StandingBack, shoulder = Double.NaN)
        }
        val malformedReport = PostureAssessmentReport.makeValidatedFixture(malformed, "2026-08-11")
        assertEquals(BodyAttentionLevel.Pending, malformedReport.overallLevel)
        assertTrue(malformedReport.reasons.any { it.contains("异常测量值") })
        assertTrue(!malformedReport.reasons.joinToString(" ").lowercase().contains("nan"))
        val incomplete = PostureAssessmentReport.makeValidatedFixture(greenSnapshots - BodyCaptureTask.Seated, "2026-08-11")
        assertEquals(BodyAttentionLevel.Pending, incomplete.overallLevel)
        val lowQuality = greenSnapshots.toMutableMap().apply { this[BodyCaptureTask.Seated] = snapshot(BodyCaptureTask.Seated).copy(sampleCount = 3, confidence = .9) }
        assertEquals(BodyAttentionLevel.Pending, PostureAssessmentReport.makeValidatedFixture(lowQuality, "2026-08-11").overallLevel)
    }

    @Test
    fun postureReportUsesHeadTiltAndBothCalibratedAtrSegments() {
        fun snapshot(task: BodyCaptureTask) = PostureMetricSnapshot(
            id = task.name, task = task, sampleCount = 18, confidence = .82,
            shoulderHeightDifferenceCm = .2, pelvicHeightDifferenceCm = .2,
            headTiltDegrees = if (task == BodyCaptureTask.StandingBack) 6.5 else 1.0,
            spinalMidlineDeviationCm = .2, thoracicRoundingDegrees = 10.0,
            forwardHeadAngleDegrees = 5.0, cameraProxyAtrDegrees = 2.0,
            cameraProxyRibProminenceCm = .2
        )
        val headTilt = BodyCaptureTask.values().associateWith(::snapshot)
        assertEquals(BodyAttentionLevel.Yellow, PostureAssessmentReport.makeValidatedFixture(headTilt, "2026-08-11").overallLevel)

        val thoracic = headTilt.toMutableMap().apply {
            this[BodyCaptureTask.StandingBack] = snapshot(BodyCaptureTask.StandingBack).copy(headTiltDegrees = 1.0)
            this[BodyCaptureTask.ForwardBend] = snapshot(BodyCaptureTask.ForwardBend).copy(thoracicAtrDegrees = 7.0)
        }
        assertEquals(BodyAttentionLevel.Red, PostureAssessmentReport.makeValidatedFixture(thoracic, "2026-08-11").overallLevel)

        val lumbar = headTilt.toMutableMap().apply {
            this[BodyCaptureTask.StandingBack] = snapshot(BodyCaptureTask.StandingBack).copy(headTiltDegrees = 1.0)
            this[BodyCaptureTask.ForwardBend] = snapshot(BodyCaptureTask.ForwardBend).copy(lumbarAtrDegrees = 5.0)
        }
        assertEquals(BodyAttentionLevel.Yellow, PostureAssessmentReport.makeValidatedFixture(lumbar, "2026-08-11").overallLevel)
    }

    @Test
    fun postureReportRequiresTaskSpecificEvidence() {
        fun sparse(task: BodyCaptureTask, shoulder: Double? = null, trunk: Double? = null, gait: Double? = null) = PostureMetricSnapshot(
            id = task.name, task = task, sampleCount = 18, confidence = .82,
            shoulderHeightDifferenceCm = shoulder, spinalMidlineDeviationCm = trunk,
            gaitShoulderSwingDifferenceCm = gait
        )
        val mismatched = BodyCaptureTask.values().associateWith { sparse(it, shoulder = .2) }
        assertEquals(BodyAttentionLevel.Pending, PostureAssessmentReport.makeValidatedFixture(mismatched, "2026-08-11").overallLevel)
        val taskSpecific = mapOf(
            BodyCaptureTask.StandingFront to sparse(BodyCaptureTask.StandingFront, shoulder = .2),
            BodyCaptureTask.StandingBack to sparse(BodyCaptureTask.StandingBack, shoulder = .2),
            BodyCaptureTask.StandingSide to sparse(BodyCaptureTask.StandingSide).copy(forwardHeadAngleDegrees = 2.0),
            BodyCaptureTask.ForwardBend to sparse(BodyCaptureTask.ForwardBend, trunk = .2),
            BodyCaptureTask.DynamicKneeControl to sparse(BodyCaptureTask.DynamicKneeControl).copy(movementRepetitionCount = 3.0),
            BodyCaptureTask.Seated to sparse(BodyCaptureTask.Seated, trunk = .2),
            BodyCaptureTask.GaitVideo to sparse(BodyCaptureTask.GaitVideo, gait = .2),
            BodyCaptureTask.FootArch to sparse(BodyCaptureTask.FootArch).copy(footArchVisibilityScore = .8)
        )
        assertEquals(BodyAttentionLevel.Green, PostureAssessmentReport.makeValidatedFixture(taskSpecific, "2026-08-11").overallLevel)
    }

    @Test
    fun postureProfileBoundaryAndNonFiniteConfidenceCannotPublish() {
        assertEquals(11.5, PostureScreeningRules.scoringProfileForAge(180).forwardHeadAttentionDegrees, 0.001)
        assertEquals(11.2, PostureScreeningRules.scoringProfileForAge(181).forwardHeadAttentionDegrees, 0.001)
        fun snapshot(task: BodyCaptureTask, confidence: Double) = PostureMetricSnapshot(
            id = task.name, task = task, sampleCount = 18, confidence = confidence,
            shoulderHeightDifferenceCm = .2, pelvicHeightDifferenceCm = .2,
            spinalMidlineDeviationCm = .2, thoracicRoundingDegrees = 10.0,
            forwardHeadAngleDegrees = 5.0, cameraProxyAtrDegrees = 2.0,
            cameraProxyRibProminenceCm = .2, gaitShoulderSwingDifferenceCm = .2,
            gaitPelvicSwingDifferenceCm = .2, gaitTrunkSwayCm = .2
        )
        val snapshots = BodyCaptureTask.values().associateWith { snapshot(it, .82) }.toMutableMap()
        snapshots[BodyCaptureTask.StandingBack] = snapshot(BodyCaptureTask.StandingBack, Double.POSITIVE_INFINITY)
        assertEquals(BodyAttentionLevel.Pending, PostureAssessmentReport.makeValidatedFixture(snapshots, "2026-08-11").overallLevel)
        assertEquals(.2, PostureMetricCalculator.range(listOf(.2, .4, .3))!!, 0.000001)
        assertEquals(null, PostureMetricCalculator.range(listOf(Double.NaN, Double.POSITIVE_INFINITY)))
    }

    @Test
    fun postureScoringBecomesMoreConservativeForYoungerChildren() {
        fun snapshot(task: BodyCaptureTask, shoulder: Double, pelvis: Double = .22, trunk: Double = .25, round: Double = 10.0, forwardHead: Double = 5.0, atr: Double = 2.0, rib: Double = 0.25): PostureMetricSnapshot {
            return when (task) {
                BodyCaptureTask.ForwardBend -> PostureMetricSnapshot(
                    id = task.name,
                    task = task,
                    sampleCount = 18,
                    confidence = .92,
                    shoulderHeightDifferenceCm = shoulder,
                    pelvicHeightDifferenceCm = pelvis,
                    spinalMidlineDeviationCm = trunk,
                    thoracicRoundingDegrees = round,
                    forwardHeadAngleDegrees = forwardHead,
                    cameraProxyAtrDegrees = atr,
                    cameraProxyRibProminenceCm = rib
                )
                BodyCaptureTask.GaitVideo -> PostureMetricSnapshot(
                    id = task.name,
                    task = task,
                    sampleCount = 18,
                    confidence = .92,
                    shoulderHeightDifferenceCm = shoulder,
                    pelvicHeightDifferenceCm = pelvis,
                    spinalMidlineDeviationCm = trunk,
                    thoracicRoundingDegrees = round,
                    forwardHeadAngleDegrees = forwardHead,
                    cameraProxyAtrDegrees = atr,
                    cameraProxyRibProminenceCm = rib,
                    gaitShoulderSwingDifferenceCm = .55,
                    gaitPelvicSwingDifferenceCm = .35,
                    gaitTrunkSwayCm = .45
                )
                else -> PostureMetricSnapshot(
                    id = task.name,
                    task = task,
                    sampleCount = 18,
                    confidence = .92,
                    shoulderHeightDifferenceCm = shoulder,
                    pelvicHeightDifferenceCm = pelvis,
                    spinalMidlineDeviationCm = trunk,
                    thoracicRoundingDegrees = round,
                    forwardHeadAngleDegrees = forwardHead,
                    cameraProxyAtrDegrees = atr,
                    cameraProxyRibProminenceCm = rib
                )
            }
        }
        val raw = mapOf(
            BodyCaptureTask.StandingBack to snapshot(BodyCaptureTask.StandingBack, shoulder = 1.15),
            BodyCaptureTask.Seated to snapshot(BodyCaptureTask.Seated, shoulder = 1.15),
            BodyCaptureTask.ForwardBend to snapshot(BodyCaptureTask.ForwardBend, shoulder = 1.15, atr = 5.0),
            BodyCaptureTask.GaitVideo to snapshot(BodyCaptureTask.GaitVideo, shoulder = 1.15)
        )
        val childReport = PostureAssessmentReport.makeValidatedFixture(raw, "2026-08-11", 80)
        val juniorReport = PostureAssessmentReport.makeValidatedFixture(raw, "2026-08-11", 120)
        assertEquals(false, childReport.overallLevel == BodyAttentionLevel.Red)
        assertEquals(false, juniorReport.overallLevel == BodyAttentionLevel.Red)
        assertEquals(true, childReport.riskScore <= juniorReport.riskScore)
    }

    @Test
    fun postureRiskScoreFallsBackWhenEvidenceIsWeak() {
        val weakSnapshot = PostureMetricSnapshot(
            id = BodyCaptureTask.StandingBack.name,
            task = BodyCaptureTask.StandingBack,
            sampleCount = 4,
            confidence = 0.58,
            shoulderHeightDifferenceCm = 2.4,
            pelvicHeightDifferenceCm = 1.7,
            spinalMidlineDeviationCm = 2.0,
            thoracicRoundingDegrees = 32.0,
            forwardHeadAngleDegrees = 20.0,
            cameraProxyAtrDegrees = 3.8,
            cameraProxyRibProminenceCm = 0.95
        )
        val lowEvidence = mapOf(
            BodyCaptureTask.StandingBack to weakSnapshot,
            BodyCaptureTask.Seated to weakSnapshot.copy(task = BodyCaptureTask.Seated, id = BodyCaptureTask.Seated.name),
            BodyCaptureTask.ForwardBend to weakSnapshot.copy(task = BodyCaptureTask.ForwardBend, id = BodyCaptureTask.ForwardBend.name, cameraProxyAtrDegrees = 3.8, cameraProxyRibProminenceCm = 0.95),
            BodyCaptureTask.GaitVideo to weakSnapshot.copy(task = BodyCaptureTask.GaitVideo, id = BodyCaptureTask.GaitVideo.name, shoulderHeightDifferenceCm = 0.0, pelvicHeightDifferenceCm = 0.0, gaitShoulderSwingDifferenceCm = 0.55, gaitPelvicSwingDifferenceCm = 0.45, gaitTrunkSwayCm = 0.45)
        )
        val report = PostureAssessmentReport.makeValidatedFixture(lowEvidence, "2026-08-11", 120)
        assertEquals(BodyAttentionLevel.Pending, report.overallLevel)
    }

    @Test
    fun incompleteLegacyDraftNeverInventsMeasurements() {
        val draft = LocalFeatureStore.legacyBodyAssessmentDraft(stage = 1, heightCm = null, weightKg = null)
        assertEquals(0.0, draft.heightCm, .001)
        assertEquals(0.0, draft.weightKg, .001)
    }

    @Test
    fun growthInsightUsesRealActivityDatesAndExplainsAdjustment() {
        val now = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse("2026-08-11")!!
        val insight = GrowthInsight.make(
            period = GrowthReportPeriod.Week,
            checkInDates = setOf("2026-08-05", "2026-08-08", "2026-08-10", "2026-07-01"),
            planDates = setOf("2026-08-08", "2026-08-11"),
            assessmentCount = 2,
            bodyAttention = BodyAttentionLevel.Yellow,
            totalScore = 28.5,
            now = now
        )

        assertEquals(4, insight.activeDays)
        assertEquals(2, insight.planDays)
        assertEquals(100, insight.consistencyPercent)
        assertEquals("姿态巩固计划", insight.planTitle)
    }

    @Test
    fun growthInsightUsesChinaBusinessTimezoneAtMidnight() {
        val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }
        val now = parser.parse("2026-08-11T00:30:00+08:00")!!
        val insight = GrowthInsight.make(GrowthReportPeriod.Week, setOf("2026-08-10"), emptySet(), 0, null, null, now)
        assertEquals(1, insight.activeDays)
    }

    @Test
    fun growthInsightDoesNotTreatAnUnpublishedSchoolScoreAsZero() {
        val now = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse("2026-08-11")!!
        val insight = GrowthInsight.make(
            period = GrowthReportPeriod.Week,
            checkInDates = setOf("2026-08-05", "2026-08-07", "2026-08-09", "2026-08-11"),
            planDates = emptySet(),
            assessmentCount = 0,
            bodyAttention = null,
            totalScore = null,
            now = now
        )

        assertEquals(100, insight.consistencyPercent)
        assertEquals("均衡成长计划", insight.planTitle)
        assertEquals(false, insight.planReason.contains("弱项"))
    }

    @Test
    fun growthInsightRejectsImpossibleCalendarDates() {
        val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssX", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.parse("2026-08-22T08:00:00Z")!!
        val insight = GrowthInsight.make(GrowthReportPeriod.Week, setOf("2026-02-31", "not-a-date"), emptySet(), 0, null, null, now)
        assertEquals(0, insight.activeDays)
        assertEquals(0, insight.planDays)
    }

    @Test
    fun growthInsightRejectsPartiallyParsedDatesButTrimsWhitespace() {
        val now = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse("2026-08-11")!!
        val insight = GrowthInsight.make(GrowthReportPeriod.Week, setOf("2026-08-10junk", " 2026-08-10 "), emptySet(), 0, null, null, now)
        assertEquals(1, insight.activeDays)
    }
}
