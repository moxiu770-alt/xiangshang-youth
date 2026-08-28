package com.xiangshang.youth.core.model

import org.json.JSONObject

/** Capture usability rules only. They never create a medical conclusion. */
object BodyCaptureQualityGate {
    enum class BodyScaleState { Invalid, TooFar, Ready, TooClose }

    const val canonicalAssetVersion = "android-v3-adams-repeatability-2026-08-27"
    const val footMinimumFrameCoverageRatio = .28
    const val footMaximumFrameCoverageRatio = .72
    data class PostureCaptureProfile(
        val tag: String,
        val staticHoldMilliseconds: Long,
        val staticMinimumFrames: Int,
        val staticMaximumDisplacementRatio: Double,
        val staticDisplacementJitterRatio: Double,
        val gaitMinimumMilliseconds: Long,
        val gaitMinimumDisplacementRatio: Double,
        val stabilityWindowFrames: Int,
        val gaitMovementWindowFrames: Int,
        val minimumRawSamplesForCompletion: Int,
        val fullBodyMinimumFrameCoverageRatio: Double,
        val seatedMinimumFrameCoverageRatio: Double,
        val minimumIndividualLandmarkConfidence: Float,
        val minimumMeanLandmarkConfidence: Float,
        val forwardBendMinimumTorsoTiltRatio: Double
    )

    data class AgeLimitedProfile(
        val minMonths: Int,
        val maxMonths: Int,
        val profile: PostureCaptureProfile
    )

    private data class ProfileOverrideToken(
        val minMonths: Int,
        val maxMonths: Int,
        val profile: PostureCaptureProfile
    )

    private val builtInProfiles = listOf(
        AgeLimitedProfile(
            72,
            96,
            PostureCaptureProfile(
                tag = "6-8岁",
                staticHoldMilliseconds = 2600L,
                staticMinimumFrames = 20,
                staticMaximumDisplacementRatio = .032,
                staticDisplacementJitterRatio = .0088,
                gaitMinimumMilliseconds = 6500L,
                gaitMinimumDisplacementRatio = .0365,
                stabilityWindowFrames = 15,
                gaitMovementWindowFrames = 7,
                minimumRawSamplesForCompletion = 18,
                fullBodyMinimumFrameCoverageRatio = .38,
                seatedMinimumFrameCoverageRatio = .145,
                minimumIndividualLandmarkConfidence = .47f,
                minimumMeanLandmarkConfidence = .515f,
                forwardBendMinimumTorsoTiltRatio = .27
            )
        ),
        AgeLimitedProfile(
            97,
            132,
            PostureCaptureProfile(
                tag = "9-11岁",
                staticHoldMilliseconds = 2500L,
                staticMinimumFrames = 20,
                staticMaximumDisplacementRatio = .031,
                staticDisplacementJitterRatio = .0078,
                gaitMinimumMilliseconds = 6300L,
                gaitMinimumDisplacementRatio = .0355,
                stabilityWindowFrames = 15,
                gaitMovementWindowFrames = 7,
                minimumRawSamplesForCompletion = 18,
                fullBodyMinimumFrameCoverageRatio = .40,
                seatedMinimumFrameCoverageRatio = .155,
                minimumIndividualLandmarkConfidence = .50f,
                minimumMeanLandmarkConfidence = .54f,
                forwardBendMinimumTorsoTiltRatio = .28
            )
        ),
        AgeLimitedProfile(
            133,
            180,
            PostureCaptureProfile(
                tag = "12-15岁",
                staticHoldMilliseconds = 2400L,
                staticMinimumFrames = 20,
                staticMaximumDisplacementRatio = .03,
                staticDisplacementJitterRatio = .0072,
                gaitMinimumMilliseconds = 6100L,
                gaitMinimumDisplacementRatio = .0368,
                stabilityWindowFrames = 14,
                gaitMovementWindowFrames = 6,
                minimumRawSamplesForCompletion = 18,
                fullBodyMinimumFrameCoverageRatio = .42,
                seatedMinimumFrameCoverageRatio = .16,
                minimumIndividualLandmarkConfidence = .52f,
                minimumMeanLandmarkConfidence = .56f,
                forwardBendMinimumTorsoTiltRatio = .28
            )
        ),
        AgeLimitedProfile(
            181,
            216,
            PostureCaptureProfile(
                tag = "16-18岁",
                staticHoldMilliseconds = 2400L,
                staticMinimumFrames = 20,
                staticMaximumDisplacementRatio = .029,
                staticDisplacementJitterRatio = .0068,
                gaitMinimumMilliseconds = 6000L,
                gaitMinimumDisplacementRatio = .038,
                stabilityWindowFrames = 14,
                gaitMovementWindowFrames = 6,
                minimumRawSamplesForCompletion = 18,
                fullBodyMinimumFrameCoverageRatio = .43,
                seatedMinimumFrameCoverageRatio = .16,
                minimumIndividualLandmarkConfidence = .53f,
                minimumMeanLandmarkConfidence = .57f,
                forwardBendMinimumTorsoTiltRatio = .28
            )
        )
    )

    private val legacy6To8Profile = builtInProfiles[0].profile
    private val legacy9To11Profile = builtInProfiles[1].profile
    private val legacy12To15Profile = builtInProfiles[2].profile
    private val legacy16PlusProfile = builtInProfiles[3].profile

    private val profileLock = Any()
    private var overrides: List<ProfileOverrideToken> = emptyList()

    /** Load sampling-informed values without a build/release cycle. */
    fun setProfileOverridesFromJson(raw: String): Boolean = runCatching {
        val root = JSONObject(raw)
        val assetVersion = root.optString("version").orEmpty()
        if (assetVersion.isNotBlank() && assetVersion != canonicalAssetVersion) {
            throw IllegalArgumentException("unsupported posture capture asset version")
        }
        val nodes = root.optJSONArray("ageProfiles") ?: throw IllegalArgumentException("missing ageProfiles")
        val parsed = mutableListOf<ProfileOverrideToken>()

        for (i in 0 until nodes.length()) {
            val profile = nodes.getJSONObject(i)
            val minMonths = profile.optInt("minAgeMonths", Int.MIN_VALUE)
            val maxMonths = profile.optInt("maxAgeMonths", Int.MAX_VALUE)
            val captureProfile = PostureCaptureProfile(
                tag = profile.optString("tag", "${'$'}{minMonths}-${'$'}{maxMonths}月"),
                staticHoldMilliseconds = profile.optLong("staticHoldMilliseconds", builtInProfiles[2].profile.staticHoldMilliseconds),
                staticMinimumFrames = profile.optInt("staticMinimumFrames", builtInProfiles[2].profile.staticMinimumFrames),
                staticMaximumDisplacementRatio = profile.optDouble("staticMaximumDisplacementRatio", builtInProfiles[2].profile.staticMaximumDisplacementRatio),
                staticDisplacementJitterRatio = profile.optDouble("staticDisplacementJitterRatio", builtInProfiles[2].profile.staticDisplacementJitterRatio),
                gaitMinimumMilliseconds = profile.optLong("gaitMinimumMilliseconds", builtInProfiles[2].profile.gaitMinimumMilliseconds),
                gaitMinimumDisplacementRatio = profile.optDouble("gaitMinimumDisplacementRatio", builtInProfiles[2].profile.gaitMinimumDisplacementRatio),
                stabilityWindowFrames = profile.optInt("stabilityWindowFrames", builtInProfiles[2].profile.stabilityWindowFrames),
                gaitMovementWindowFrames = profile.optInt("gaitMovementWindowFrames", builtInProfiles[2].profile.gaitMovementWindowFrames),
                minimumRawSamplesForCompletion = profile.optInt("minimumRawSamplesForCompletion", builtInProfiles[2].profile.minimumRawSamplesForCompletion),
                fullBodyMinimumFrameCoverageRatio = profile.optDouble("fullBodyMinimumFrameCoverageRatio", builtInProfiles[2].profile.fullBodyMinimumFrameCoverageRatio),
                seatedMinimumFrameCoverageRatio = profile.optDouble("seatedMinimumFrameCoverageRatio", builtInProfiles[2].profile.seatedMinimumFrameCoverageRatio),
                minimumIndividualLandmarkConfidence = profile.optDouble("minimumIndividualLandmarkConfidence", builtInProfiles[2].profile.minimumIndividualLandmarkConfidence.toDouble()).toFloat(),
                minimumMeanLandmarkConfidence = profile.optDouble("minimumMeanLandmarkConfidence", builtInProfiles[2].profile.minimumMeanLandmarkConfidence.toDouble()).toFloat(),
                forwardBendMinimumTorsoTiltRatio = profile.optDouble("forwardBendMinimumTorsoTiltRatio", builtInProfiles[2].profile.forwardBendMinimumTorsoTiltRatio)
            )

            if (minMonths == Int.MIN_VALUE || maxMonths == Int.MAX_VALUE || minMonths < 0 || maxMonths < minMonths || maxMonths > 240 || !captureProfile.isValid()) {
                throw IllegalArgumentException("invalid age profile")
            }
            parsed += ProfileOverrideToken(minMonths, maxMonths, captureProfile)
        }

        if (parsed.isEmpty()) throw IllegalArgumentException("invalid ageProfiles")
        if (assetVersion.isNotBlank()) {
            val expectedBands = listOf(72 to 96, 97 to 132, 133 to 180, 181 to 216)
            val actualBands = parsed.map { it.minMonths to it.maxMonths }
            if (actualBands != expectedBands) throw IllegalArgumentException("incomplete posture capture canonical asset")
        }
        parsed.sortWith(compareBy({ it.minMonths }, { it.maxMonths }))
        synchronized(profileLock) { overrides = parsed }
        true
    }.getOrNull() == true

    private fun PostureCaptureProfile.isValid(): Boolean {
        fun ratio(value: Double, upper: Double = 1.0) = value.isFinite() && value in 0.0..upper
        fun positive(value: Long) = value in 100L..30_000L
        return positive(staticHoldMilliseconds) && staticMinimumFrames in 3..240 &&
            ratio(staticMaximumDisplacementRatio) && ratio(staticDisplacementJitterRatio) &&
            positive(gaitMinimumMilliseconds) && ratio(gaitMinimumDisplacementRatio) &&
            stabilityWindowFrames in 3..240 && gaitMovementWindowFrames in 2..120 &&
            minimumRawSamplesForCompletion in 1..10_000 && ratio(fullBodyMinimumFrameCoverageRatio) &&
            ratio(seatedMinimumFrameCoverageRatio) && minimumIndividualLandmarkConfidence.isFinite() && minimumIndividualLandmarkConfidence in 0f..1f &&
            minimumMeanLandmarkConfidence.isFinite() && minimumMeanLandmarkConfidence in 0f..1f &&
            ratio(forwardBendMinimumTorsoTiltRatio)
    }

    /** Reset to the built-in age profiles. */
    fun clearProfileOverrides() = synchronized(profileLock) { overrides = emptyList() }

    private fun fallbackProfile(ageMonths: Int): PostureCaptureProfile {
        val source = builtInProfiles
        return source.firstOrNull { ageMonths in it.minMonths..it.maxMonths }?.profile
            ?: source.last { ageMonths >= it.minMonths }.profile
    }

    private fun overrideProfile(ageMonths: Int): PostureCaptureProfile {
        val currentOverrides = synchronized(profileLock) { overrides }
        val matched = currentOverrides.firstOrNull { ageMonths in it.minMonths..it.maxMonths }
        if (matched != null) return matched.profile
        return fallbackProfile(ageMonths)
    }

    // Backward-compatible legacy constants used by UI labels and existing tests.
    const val staticHoldMilliseconds = 2500L
    const val staticMinimumFrames = 20
    /** 单次单帧位移上限（相对身高归一化后）。 */
    const val staticMaximumDisplacementRatio = .029
    /** 动作完成抖动门限：当短窗内抖动上升超过该值则重置。 */
    const val staticDisplacementJitterRatio = .0072
    const val gaitMinimumMilliseconds = 6300L
    /** 步态必须有持续位移，不是一次抖动。 */
    const val gaitMinimumDisplacementRatio = .0368
    /** 过滤单次抖动的滑窗长度。 */
    const val stabilityWindowFrames = 15
    /** 步态需要连续几帧维持移动迹象。 */
    const val gaitMovementWindowFrames = 6
    /** 快速拒绝噪声前最少可用原始样本。 */
    const val minimumRawSamplesForCompletion = 18
    /** Pose confidence alone is insufficient when the child is too far away. */
    const val fullBodyMinimumFrameCoverageRatio = .42
    const val seatedMinimumFrameCoverageRatio = .16
    /** Upper framing bounds keep capture in a long shot and reduce perspective
     * distortion around shoulders and hips. */
    const val fullBodyMaximumFrameCoverageRatio = .70
    const val seatedMaximumFrameCoverageRatio = .36
    const val followAlongMaximumBodySpanRatio = .78
    const val followAlongMaximumTorsoSpanRatio = .34
    /** Requires every key joint to be reliable, not merely one detected frame.
     * This is a framing-quality gate and must not be interpreted as a body or
     * medical score. */
    const val minimumIndividualLandmarkConfidence = .50f
    const val minimumMeanLandmarkConfidence = .56f
    /** Visual completion only, never a flexibility/medical score. */
    const val forwardBendMinimumTorsoTiltRatio = .28
    /** Manual requirement: knees fully extended, with landmark jitter tolerance. */
    const val adamsMinimumKneeExtensionDegrees = 165.0

    fun profileForAge(ageMonths: Int?): PostureCaptureProfile = when {
        ageMonths == null -> fallbackProfile(108)
        ageMonths < builtInProfiles.first().minMonths -> fallbackProfile(builtInProfiles.first().minMonths)
        ageMonths > builtInProfiles.last().maxMonths -> fallbackProfile(builtInProfiles.last().maxMonths)
        builtInProfiles.any { ageMonths in it.minMonths..it.maxMonths } -> overrideProfile(ageMonths)
        else -> overrideProfile(ageMonths)
    }

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, ageMonths: Int?): Boolean =
        staticReady(elapsedMs, stableFrames, displacementRatio, 0.0, ageMonths)

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, displacementJitterRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return elapsedMs >= 0 && displacementRatio.isFinite() && displacementJitterRatio.isFinite() && displacementRatio >= 0 && displacementJitterRatio >= 0 && elapsedMs >= profile.staticHoldMilliseconds && stableFrames >= profile.staticMinimumFrames && displacementRatio < profile.staticMaximumDisplacementRatio && displacementJitterRatio <= profile.staticDisplacementJitterRatio
    }

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double): Boolean = staticReady(elapsedMs, stableFrames, displacementRatio, 0.0, null)

    fun staticReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, displacementJitterRatio: Double): Boolean = staticReady(elapsedMs, stableFrames, displacementRatio, displacementJitterRatio, null)

    fun gaitReady(elapsedMs: Long, displacementRatio: Double, movementSamples: Int, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return elapsedMs >= 0 && displacementRatio.isFinite() && displacementRatio >= profile.gaitMinimumDisplacementRatio && elapsedMs >= profile.gaitMinimumMilliseconds && movementSamples >= profile.gaitMovementWindowFrames
    }

    fun gaitReady(elapsedMs: Long, displacementRatio: Double, movementSamples: Int): Boolean = gaitReady(elapsedMs, displacementRatio, movementSamples, null)

    fun gaitReady(elapsedMs: Long, displacementRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return gaitReady(elapsedMs, displacementRatio, profile.gaitMovementWindowFrames, ageMonths)
    }

    fun gaitReady(elapsedMs: Long, displacementRatio: Double): Boolean = gaitReady(elapsedMs, displacementRatio, null)

    fun forwardBendReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, torsoTiltRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return staticReady(elapsedMs, stableFrames, displacementRatio, 0.0, ageMonths) && torsoTiltRatio.isFinite() && torsoTiltRatio in 0.0..10.0 && torsoTiltRatio >= profile.forwardBendMinimumTorsoTiltRatio
    }

    fun forwardBendReady(elapsedMs: Long, stableFrames: Int, displacementRatio: Double, torsoTiltRatio: Double): Boolean = forwardBendReady(elapsedMs, stableFrames, displacementRatio, torsoTiltRatio, null)

    fun hasUsableBodyScale(verticalCoverageRatio: Double, seated: Boolean, ageMonths: Int?): Boolean {
        return bodyScaleState(verticalCoverageRatio, seated, ageMonths) == BodyScaleState.Ready
    }

    fun bodyScaleState(verticalCoverageRatio: Double, seated: Boolean, ageMonths: Int?): BodyScaleState {
        if (!verticalCoverageRatio.isFinite() || verticalCoverageRatio !in 0.0..1.0) return BodyScaleState.Invalid
        val profile = profileForAge(ageMonths)
        val minimum = if (seated) profile.seatedMinimumFrameCoverageRatio else profile.fullBodyMinimumFrameCoverageRatio
        val maximum = if (seated) seatedMaximumFrameCoverageRatio else fullBodyMaximumFrameCoverageRatio
        return when {
            verticalCoverageRatio < minimum -> BodyScaleState.TooFar
            verticalCoverageRatio > maximum -> BodyScaleState.TooClose
            else -> BodyScaleState.Ready
        }
    }

    fun bodyScaleState(verticalCoverageRatio: Double, seated: Boolean): BodyScaleState = bodyScaleState(verticalCoverageRatio, seated, null)

    fun footScaleState(lowerLegCoverageRatio: Double): BodyScaleState = when {
        !lowerLegCoverageRatio.isFinite() || lowerLegCoverageRatio !in 0.0..1.0 -> BodyScaleState.Invalid
        lowerLegCoverageRatio < footMinimumFrameCoverageRatio -> BodyScaleState.TooFar
        lowerLegCoverageRatio > footMaximumFrameCoverageRatio -> BodyScaleState.TooClose
        else -> BodyScaleState.Ready
    }

    fun hasUsableBodyScale(verticalCoverageRatio: Double, seated: Boolean): Boolean = hasUsableBodyScale(verticalCoverageRatio, seated, null)

    fun hasComfortableFollowAlongFraming(bodySpanRatio: Double?, torsoSpanRatio: Double?): Boolean {
        val validBody = bodySpanRatio?.let { it.isFinite() && it in 0.0..1.5 } ?: true
        val validTorso = torsoSpanRatio?.let { it.isFinite() && it in 0.0..1.5 } ?: true
        if (!validBody || !validTorso) return false
        return (bodySpanRatio ?: 0.0) <= followAlongMaximumBodySpanRatio &&
            (torsoSpanRatio ?: 0.0) <= followAlongMaximumTorsoSpanRatio
    }

    /** Camera image coordinates grow downward; shoulders must remain above hips. */
    fun hasUsableSeatedGeometry(shoulderCenterY: Double, hipCenterY: Double, verticalCoverageRatio: Double, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return shoulderCenterY.isFinite() && hipCenterY.isFinite() && verticalCoverageRatio.isFinite() && verticalCoverageRatio in 0.0..1.0 && shoulderCenterY < hipCenterY && verticalCoverageRatio >= profile.seatedMinimumFrameCoverageRatio
    }

    fun hasUsableSeatedGeometry(shoulderCenterY: Double, hipCenterY: Double, verticalCoverageRatio: Double): Boolean = hasUsableSeatedGeometry(shoulderCenterY, hipCenterY, verticalCoverageRatio, null)

    fun hasReliableLandmarks(confidences: List<Float>, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        return confidences.isNotEmpty() && confidences.all { it.isFinite() && it in 0f..1f && it >= profile.minimumIndividualLandmarkConfidence } && confidences.average() >= profile.minimumMeanLandmarkConfidence.toDouble()
    }

    /** Feet are together in the Adams position, so one ankle can visually
     * overlap the other. Keep the torso strict while accepting one reliable
     * ankle for the capture-completion gate. */
    fun hasReliableForwardBendLandmarks(core: List<Float>, ankles: List<Float>, ageMonths: Int?): Boolean {
        val profile = profileForAge(ageMonths)
        val individualFloor = maxOf(.35f, profile.minimumIndividualLandmarkConfidence - .08f)
        val meanFloor = maxOf(.42f, profile.minimumMeanLandmarkConfidence - .05f)
        return core.isNotEmpty() && core.all { it.isFinite() && it in 0f..1f && it >= individualFloor } &&
            core.average() >= meanFloor.toDouble() && ankles.any { it.isFinite() && it in 0f..1f && it >= profile.minimumIndividualLandmarkConfidence }
    }

}
