package com.xiangshang.youth

import com.xiangshang.youth.feature.parent.ChildFollowAlongTuning
import com.xiangshang.youth.feature.parent.FollowAlongActionProfile
import com.xiangshang.youth.feature.parent.FollowAlongAgeProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import org.json.JSONObject

private fun resolveFollowAlongProfileJson(): String {
    val workingDirectory = File(requireNotNull(System.getProperty("user.dir")))
    val candidatePaths = listOf(
        workingDirectory.resolve("src/main/assets/follow_along_action_profiles.json"),
        workingDirectory.resolve("app/src/main/assets/follow_along_action_profiles.json"),
        workingDirectory.resolve("android/app/src/main/assets/follow_along_action_profiles.json")
    )

    val file = candidatePaths.firstOrNull { it.exists() }
    return requireNotNull(file) { "follow_along_action_profiles.json not found in ${candidatePaths.joinToString()}" }
        .readText()
}

class FollowAlongTuningTest {
    @Test
    fun modelVersionIsExplicitAndAuditable() {
        assertEquals("UY-FOLLOW-CV-1.0", ChildFollowAlongTuning.algorithmVersion)
        assertEquals("UY-CAL-BASELINE-1.0", ChildFollowAlongTuning.calibrationVersion)
    }

    @Test
    fun ageProfileUsesChildBiasAndCalibrationWindow() {
        val child = ChildFollowAlongTuning.profileForAge(84)
        val junior = ChildFollowAlongTuning.profileForAge(108)

        assertEquals("6-8岁", child.label)
        assertEquals("9-11岁", junior.label)
        assertTrue(child.calibrationFrames > junior.calibrationFrames)
        assertTrue(child.dynamicGateFloor < junior.dynamicGateFloor)
    }

    @Test
    fun actionProfileFillsAllProfilesWithoutCrash() {
        val categories = listOf(
            "front_raise",
            "lateral_raise",
            "squat",
            "lunge",
            "jumping_jack",
            "high_knee",
            "sit_up",
            "plank",
            "burpee",
            "squat_challenge",
            "jump_rope",
            "unknown"
        )
        val ageProfile = ChildFollowAlongTuning.profileForAge(96)
        val profiles = categories.associateWith { ChildFollowAlongTuning.actionProfileFor(it, ageProfile) }

        assertTrue(profiles.values.all { it.minSignalRange > 0f })
        assertTrue(profiles.values.all { it.minRepIntervalMs >= 320L })
        assertTrue(profiles.values.all { it.requiredSignalHistoryFrames >= 10 })
    }

    @Test
    fun actionProfileMonotonicityMatchesSmootherChildProfile() {
        val toddler = ChildFollowAlongTuning.profileForAge(84)
        val normal = ChildFollowAlongTuning.profileForAge(120)
        val older = ChildFollowAlongTuning.profileForAge(170)
        val fast = ChildFollowAlongTuning.actionProfileFor("jumping_jack", toddler)
        val normalProfile = ChildFollowAlongTuning.actionProfileFor("jumping_jack", normal)
        val slowProfile = ChildFollowAlongTuning.actionProfileFor("jumping_jack", older)

        // 大孩子/更大体型在同一动作中通常可收敛更快，因此更小年龄区间应具有更长的防抖间隔。
        assertTrue(fast.minRepIntervalMs >= normalProfile.minRepIntervalMs)
        assertTrue(fast.minRepIntervalMs >= slowProfile.minRepIntervalMs)
        assertTrue(normalProfile.requiredSignalHistoryFrames >= 12)
        assertTrue(slowProfile.rangeNoiseMultiplier >= 2.2f)
    }

    @Test
    fun dynamicRangeBoundariesNotCollapsing() {
        val ageProfile = ChildFollowAlongTuning.profileForAge(108)
        val profile: FollowAlongActionProfile = ChildFollowAlongTuning.actionProfileFor("high_knee", ageProfile)

        assertTrue(profile.settlingFrames >= 2)
        assertTrue(profile.rangeNoiseMultiplier > 2.0f)
        assertTrue(ageProfile.dynamicGateFloor > 0.5f)
        assertTrue(ageProfile.dynamicGateFloor < ageProfile.dynamicGateCeiling)
    }

    @Test
    fun jsonOverridesCanInjectChildAndAdultThresholds() {
        val raw = resolveFollowAlongProfileJson()
        val applyResult = ChildFollowAlongTuning.setProfileOverridesFromJson(raw)
        if (!applyResult) {
            ChildFollowAlongTuning.clearProfileOverrides()
        }
        assertTrue(applyResult)

        val child = ChildFollowAlongTuning.profileForAge(84)
        val older = ChildFollowAlongTuning.profileForAge(180)
        val childAction = ChildFollowAlongTuning.actionProfileFor("high_knee", child, 84)
        val olderAction = ChildFollowAlongTuning.actionProfileFor("high_knee", older, 180)

        assertTrue(child.calibrationFrames > older.calibrationFrames)
        assertTrue(childAction.minRepIntervalMs > olderAction.minRepIntervalMs)
        assertTrue(childAction.minSignalRange < olderAction.minSignalRange)
        assertTrue(childAction.requiredSignalHistoryFrames >= olderAction.requiredSignalHistoryFrames)

        ChildFollowAlongTuning.clearProfileOverrides()
    }

    @Test
    fun actionProfileAdjustmentsRemainComposableAndDeterministic() {
        val childAge = ChildFollowAlongTuning.profileForAge(84)
        val olderAge = ChildFollowAlongTuning.profileForAge(180)
        val childAction = ChildFollowAlongTuning.actionProfileFor("jumping_jack", childAge, 84)
        val olderAction = ChildFollowAlongTuning.actionProfileFor("jumping_jack", olderAge, 180)

        assertTrue(childAction.minRepIntervalMs >= olderAction.minRepIntervalMs)
        assertTrue(childAction.activeGateRatio > 0f)
        assertTrue(olderAction.activeGateRatio > 0f)
        assertTrue(childAction.requiredSignalHistoryFrames >= 10)
        assertTrue(olderAction.requiredSignalHistoryFrames >= 10)
    }

    @Test
    fun childAgeHasHigherReturnStabilityDefaults() {
        val childAge = ChildFollowAlongTuning.profileForAge(84)
        val juniorAge = ChildFollowAlongTuning.profileForAge(108)
        val adultAge = ChildFollowAlongTuning.profileForAge(180)

        val childJump = ChildFollowAlongTuning.actionProfileFor("front_raise", childAge, 84)
        val juniorJump = ChildFollowAlongTuning.actionProfileFor("front_raise", juniorAge, 108)
        val adultJump = ChildFollowAlongTuning.actionProfileFor("front_raise", adultAge, 180)

        assertTrue(childJump.minRepIntervalMs >= juniorJump.minRepIntervalMs)
        assertTrue(childJump.minRepIntervalMs >= adultJump.minRepIntervalMs)
        assertTrue(childJump.requiredSignalHistoryFrames >= juniorJump.requiredSignalHistoryFrames)
        assertTrue(childJump.settlingFrames >= juniorJump.settlingFrames)
        assertTrue(childJump.stableReturnFrames >= adultJump.stableReturnFrames)
        assertTrue(childJump.stablePeakFrames >= adultJump.stablePeakFrames)
    }

    @Test
    fun actionProfilesAreExplicitByFourAgeSegmentsForPrimaryMoves() {
        val child6_8 = ChildFollowAlongTuning.profileForAge(84)
        val junior9_11 = ChildFollowAlongTuning.profileForAge(108)
        val junior11_14 = ChildFollowAlongTuning.profileForAge(150)
        val teen14_18 = ChildFollowAlongTuning.profileForAge(186)

        val jumpRope6_8 = ChildFollowAlongTuning.actionProfileFor("jump_rope", child6_8, 84)
        val jumpRope9_11 = ChildFollowAlongTuning.actionProfileFor("jump_rope", junior9_11, 108)
        val jumpRope11_14 = ChildFollowAlongTuning.actionProfileFor("jump_rope", junior11_14, 150)
        val jumpRope14_18 = ChildFollowAlongTuning.actionProfileFor("jump_rope", teen14_18, 186)

        assertTrue(jumpRope6_8.maxRepIntervalMs > jumpRope14_18.maxRepIntervalMs)
        assertTrue(jumpRope6_8.minRepIntervalMs >= jumpRope9_11.minRepIntervalMs)
        assertTrue(jumpRope9_11.minRepIntervalMs >= jumpRope11_14.minRepIntervalMs)
        assertTrue(jumpRope11_14.topHoldFrames >= jumpRope14_18.topHoldFrames)
        assertTrue(jumpRope6_8.returnHoldFrames >= jumpRope14_18.returnHoldFrames)
        assertTrue(jumpRope6_8.minDropRatio >= jumpRope14_18.minDropRatio)
    }

    @Test
    fun jsonSupportsStricterChildReturnConstraintsForHighKnee() {
        val raw = resolveFollowAlongProfileJson()
        assertTrue(ChildFollowAlongTuning.setProfileOverridesFromJson(raw))

        val child = ChildFollowAlongTuning.actionProfileFor(
            "high_knee",
            ChildFollowAlongTuning.profileForAge(84),
            84
        )
        val junior = ChildFollowAlongTuning.actionProfileFor(
            "high_knee",
            ChildFollowAlongTuning.profileForAge(150),
            150
        )

        assertTrue(child.minDropRatio >= 0.32f)
        assertTrue(child.returnSlopeMinRatio > junior.returnSlopeMinRatio)
        assertTrue(child.returnConfidenceFloor >= junior.returnConfidenceFloor)
        assertTrue(child.minDropAbsolute > junior.minDropAbsolute)

        ChildFollowAlongTuning.clearProfileOverrides()
    }

    @Test
    fun childProfileUsesStrongerHoldFramesForPeakAndReturn() {
        val child6_8 = ChildFollowAlongTuning.profileForAge(90)
        val child9_11 = ChildFollowAlongTuning.profileForAge(120)
        val older = ChildFollowAlongTuning.profileForAge(180)
        val childProfile = ChildFollowAlongTuning.actionProfileFor("jumping_jack", child6_8, 90)
        val juniorProfile = ChildFollowAlongTuning.actionProfileFor("jumping_jack", child9_11, 120)
        val adultProfile = ChildFollowAlongTuning.actionProfileFor("jumping_jack", older, 180)

        assertTrue(childProfile.topHoldFrames >= juniorProfile.topHoldFrames)
        assertTrue(juniorProfile.topHoldFrames >= adultProfile.topHoldFrames)
        assertTrue(childProfile.returnHoldFrames >= juniorProfile.returnHoldFrames)
        assertTrue(juniorProfile.returnHoldFrames >= adultProfile.returnHoldFrames)
        assertTrue(childProfile.minRepIntervalMs >= adultProfile.minRepIntervalMs)
        assertTrue(childProfile.requiredSignalHistoryFrames >= adultProfile.requiredSignalHistoryFrames)
    }

    @Test
    fun childPrecisionModeFurtherTightensHighSpeedMoves() {
        val child = ChildFollowAlongTuning.profileForAge(84)
        val junior = ChildFollowAlongTuning.profileForAge(110)
        val older = ChildFollowAlongTuning.profileForAge(170)

        val childJumpRope = ChildFollowAlongTuning.actionProfileFor("jump_rope", child, 84)
        val juniorJumpRope = ChildFollowAlongTuning.actionProfileFor("jump_rope", junior, 110)
        val adultJumpRope = ChildFollowAlongTuning.actionProfileFor("jump_rope", older, 170)

        assertTrue(childJumpRope.minRepIntervalMs >= juniorJumpRope.minRepIntervalMs)
        assertTrue(childJumpRope.minRepIntervalMs >= adultJumpRope.minRepIntervalMs)
        assertTrue(childJumpRope.topHoldFrames >= juniorJumpRope.topHoldFrames)
        assertTrue(childJumpRope.returnHoldFrames >= juniorJumpRope.returnHoldFrames)
        assertTrue(childJumpRope.minDropRatio >= juniorJumpRope.minDropRatio)
        assertTrue(childJumpRope.returnConfidenceFloor >= juniorJumpRope.returnConfidenceFloor)

        val childJump = ChildFollowAlongTuning.actionProfileFor("high_knee", child, 84)
        val juniorJump = ChildFollowAlongTuning.actionProfileFor("high_knee", junior, 110)
        assertTrue(childJump.returnSlopeMinRatio >= juniorJump.returnSlopeMinRatio)
        assertTrue(childJump.topHoldFrames >= juniorJump.topHoldFrames)
    }

    @Test
    fun jsonOverridesMustCarryHoldThresholdFields() {
        val raw = resolveFollowAlongProfileJson()
        val parsed = JSONObject(raw)
        val actionProfiles = parsed.getJSONArray("actionProfiles")
        val requiredCats = setOf(
            "front_raise", "lateral_raise", "squat", "lunge", "jumping_jack", "high_knee", "sit_up",
            "plank", "burpee", "squat_challenge", "jump_rope"
        )

        val categories = mutableSetOf<String>()
        val requiredProfileKeys = setOf(
            "minSignalRange",
            "minRepIntervalMs",
            "highGateRatio",
            "lowGateRatio",
            "topHoldFrames",
            "returnHoldFrames",
            "maxRepIntervalMs",
            "minDropRatio",
            "minDropAbsolute",
            "returnSlopeMinRatio",
            "returnConfidenceFloor",
            "requiredSignalHistoryFrames",
            "historyLen"
        )
        var totalPositiveRanges = 0
        for (i in 0 until actionProfiles.length()) {
            val node = actionProfiles.getJSONObject(i)
            val category = node.getString("category")
            if (requiredCats.contains(category)) {
                categories.add(category)
                requiredProfileKeys.forEach { key -> assertTrue("$key missing for ${category}[${node.getInt("minAgeMonths")}-${node.getInt("maxAgeMonths")}]", node.has(key)) }
                assertTrue(node.getInt("topHoldFrames") > 0)
                assertTrue(node.getInt("returnHoldFrames") > 0)
            }
            totalPositiveRanges += node.optInt("minHistory", 0)
        }

        assertTrue(categories.containsAll(requiredCats))
        assertTrue(totalPositiveRanges > 0)
    }

    @Test
    fun jsonProfileLoadKeepsChildStrongerGateForJumpRope() {
        val raw = resolveFollowAlongProfileJson()
        val applyResult = ChildFollowAlongTuning.setProfileOverridesFromJson(raw)
        if (!applyResult) ChildFollowAlongTuning.clearProfileOverrides()
        assertTrue(applyResult)

        val childProfile = ChildFollowAlongTuning.actionProfileFor(
            "jump_rope",
            ChildFollowAlongTuning.profileForAge(84),
            84
        )
        val childJuniorProfile = ChildFollowAlongTuning.actionProfileFor(
            "jump_rope",
            ChildFollowAlongTuning.profileForAge(108),
            108
        )
        val juniorProfile = ChildFollowAlongTuning.actionProfileFor(
            "jump_rope",
            ChildFollowAlongTuning.profileForAge(180),
            180
        )

        assertTrue(childProfile.topHoldFrames >= childJuniorProfile.topHoldFrames)
        assertTrue(childJuniorProfile.topHoldFrames >= juniorProfile.topHoldFrames)
        assertTrue(childProfile.returnHoldFrames >= childJuniorProfile.returnHoldFrames)
        assertTrue(childJuniorProfile.returnHoldFrames >= juniorProfile.returnHoldFrames)
        assertTrue(childProfile.minRepIntervalMs >= juniorProfile.minRepIntervalMs)

        ChildFollowAlongTuning.clearProfileOverrides()
    }

    @Test
    fun jsonOverrideSupportsReturnAndDropFields() {
        val sampleJson = """
            {
              "ageProfiles": [
                {"minAgeMonths":72,"maxAgeMonths":216,"tag":"6-16岁","minLandmarkConfidence":0.32,"minAverageConfidence":0.44,"calibrationFrames":24,"stablePeakFrames":4,"stableReturnFrames":4,"minRepIntervalMs":650,"amplitudeScale":0.88,"activeGateRatio":0.55,"lowGateRatio":0.33,"qualityAmplitudeWeight":0.56,"signalToleranceScale":1.0,"intervalScale":1.0,"smoothScale":1.0,"outlierTrimRatio":0.12,"stabilityGateScale":1.0,"dynamicGateFloor":0.70,"dynamicGateCeiling":1.25,"confidenceWindowFrames":20}
              ],
              "actionProfiles": [
                {
                  "category": "front_raise",
                  "minAgeMonths": 72,
                  "maxAgeMonths": 216,
                  "minSignalRange": 0.094,
                  "minRepIntervalMs": 700,
                  "minDropRatio": 0.31,
                  "minDropAbsolute": 0.0075,
                  "returnSlopeMinRatio": 0.95,
                  "returnConfidenceFloor": 0.82,
                  "maxRepIntervalMs": 1700,
                  "highGateRatio": 0.25,
                  "lowGateRatio": 0.18,
                  "historyLen": 40,
                  "minHistory": 6
                }
              ]
            }
        """.trimIndent()

        assertTrue(ChildFollowAlongTuning.setProfileOverridesFromJson(sampleJson))
        val childProfile = ChildFollowAlongTuning.actionProfileFor("front_raise", ChildFollowAlongTuning.profileForAge(84), 84)

        assertTrue(childProfile.minDropRatio >= 0.30f)
        assertTrue(childProfile.minDropAbsolute > 0f)
        assertTrue(childProfile.returnSlopeMinRatio > 0.9f)
        assertTrue(childProfile.returnConfidenceFloor > 0.80f)
        assertTrue(childProfile.maxRepIntervalMs > childProfile.minRepIntervalMs * 2)

        ChildFollowAlongTuning.clearProfileOverrides()
    }

    @Test
    fun jsonOverridesRejectNonFiniteOrUnsafeActionThresholds() {
        val unsafe = """
            {"actionProfiles":[{"category":"squat","minAgeMonths":72,"maxAgeMonths":216,"minSignalRange":0.08,"historyLen":4,"minHistory":6,"highGateRatio":0.2,"lowGateRatio":0.1,"minRepIntervalMs":700,"maxRepIntervalMs":2000,"returnConfidenceFloor":9}]}
        """.trimIndent()
        assertEquals(false, ChildFollowAlongTuning.setProfileOverridesFromJson(unsafe))
        ChildFollowAlongTuning.clearProfileOverrides()
    }

    @Test
    fun versionedFollowAssetMustContainCompleteAgeAndActionMatrix() {
        val incomplete = """
            {"meta":{"version":"android-child-precision-2026-09-16-child-motion-research-v4.1"},
             "ageProfiles":[{"minAgeMonths":72,"maxAgeMonths":216}],
             "actionProfiles":[]}
        """.trimIndent()
        assertEquals(false, ChildFollowAlongTuning.setProfileOverridesFromJson(incomplete))
        ChildFollowAlongTuning.clearProfileOverrides()
    }

    @Test
    fun actionProfileMaxReturnWindowShouldKeepYouFromDoubleCounting() {
        val child = ChildFollowAlongTuning.profileForAge(84)
        val junior = ChildFollowAlongTuning.profileForAge(108)
        val older = ChildFollowAlongTuning.profileForAge(180)
        val childProfile = ChildFollowAlongTuning.actionProfileFor("plank", child, 84)
        val juniorProfile = ChildFollowAlongTuning.actionProfileFor("plank", junior, 108)
        val adultProfile = ChildFollowAlongTuning.actionProfileFor("plank", older, 180)

        assertTrue(childProfile.maxRepIntervalMs >= childProfile.minRepIntervalMs * 2)
        assertTrue(juniorProfile.maxRepIntervalMs >= juniorProfile.minRepIntervalMs * 2)
        assertTrue(adultProfile.maxRepIntervalMs >= adultProfile.minRepIntervalMs * 2)

        assertTrue(childProfile.minDropRatio > 0f)
        assertTrue(childProfile.returnConfidenceFloor >= adultProfile.returnConfidenceFloor)
        assertTrue(childProfile.returnSlopeMinRatio >= adultProfile.returnSlopeMinRatio)
    }

    @Test
    fun jsonSchemaShouldKeepSingleTopLevelVersionAndMatchMeta() {
        val raw = resolveFollowAlongProfileJson()
        val parsed = JSONObject(raw)

        // top-level only keeps keys used by runtime parser
        assertTrue(!parsed.has("version"))
        assertTrue(parsed.has("meta"))
        assertTrue(parsed.has("actionProfiles"))
        assertTrue(parsed.has("ageProfiles"))
        val meta = parsed.getJSONObject("meta")
        assertTrue(meta.has("version"))

        // 保证元版本和顶层约定值一致（如有变更可快速发现）
        assertEquals(meta.getString("version"), "android-child-precision-2026-09-16-child-motion-research-v4.1")
    }

    @Test
    fun child6To8SpeedMoveProfilesAreStricterAfterOnlineSamplingTuning() {
        val raw = resolveFollowAlongProfileJson()
        assertTrue(ChildFollowAlongTuning.setProfileOverridesFromJson(raw))

        val childBand = ChildFollowAlongTuning.profileForAge(84)
        val juniorBand = ChildFollowAlongTuning.profileForAge(120)
        val adultBand = ChildFollowAlongTuning.profileForAge(180)

        val childJumpRope = ChildFollowAlongTuning.actionProfileFor("jump_rope", childBand, 84)
        val juniorJumpRope = ChildFollowAlongTuning.actionProfileFor("jump_rope", juniorBand, 120)
        val adultJumpRope = ChildFollowAlongTuning.actionProfileFor("jump_rope", adultBand, 180)

        val childJack = ChildFollowAlongTuning.actionProfileFor("jumping_jack", childBand, 84)
        val juniorJack = ChildFollowAlongTuning.actionProfileFor("jumping_jack", juniorBand, 120)

        val childKnee = ChildFollowAlongTuning.actionProfileFor("high_knee", childBand, 84)
        val juniorKnee = ChildFollowAlongTuning.actionProfileFor("high_knee", juniorBand, 120)

        assertTrue(childJumpRope.minRepIntervalMs >= juniorJumpRope.minRepIntervalMs)
        assertTrue(childJumpRope.topHoldFrames >= juniorJumpRope.topHoldFrames)
        assertTrue(childJumpRope.returnHoldFrames >= juniorJumpRope.returnHoldFrames)
        assertTrue(childJumpRope.minDropRatio >= juniorJumpRope.minDropRatio)
        assertTrue(childJumpRope.minDropAbsolute >= juniorJumpRope.minDropAbsolute)
        assertTrue(childJumpRope.returnSlopeMinRatio >= juniorJumpRope.returnSlopeMinRatio)

        assertTrue(childJack.minRepIntervalMs >= juniorJack.minRepIntervalMs)
        assertTrue(childJack.topHoldFrames >= juniorJack.topHoldFrames)
        assertTrue(childJack.returnHoldFrames >= juniorJack.returnHoldFrames)

        assertTrue(childKnee.topHoldFrames >= juniorKnee.topHoldFrames)
        assertTrue(childKnee.returnHoldFrames >= juniorKnee.returnHoldFrames)
        assertTrue(childKnee.returnSlopeMinRatio >= juniorKnee.returnSlopeMinRatio)
        assertTrue(juniorJumpRope.minDropRatio >= adultJumpRope.minDropRatio)

        ChildFollowAlongTuning.clearProfileOverrides()
    }
}
