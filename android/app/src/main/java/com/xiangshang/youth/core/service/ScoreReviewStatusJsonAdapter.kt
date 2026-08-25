package com.xiangshang.youth.core.service

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.JsonReader.Token
import com.xiangshang.youth.core.model.ScoreReviewStatus

/**
 * Network compatibility boundary for score review state.
 * Unknown or missing states are not trusted: they decode as PendingReview so a
 * malformed field payload cannot make an unverified score appear published.
 */
internal class ScoreReviewStatusJsonAdapter : JsonAdapter<ScoreReviewStatus>() {
    override fun fromJson(reader: JsonReader): ScoreReviewStatus {
        if (reader.peek() == Token.NULL) {
            reader.nextNull<Unit>()
            return ScoreReviewStatus.PendingReview
        }
        return when (reader.nextString()) {
            "passed" -> ScoreReviewStatus.Passed
            "pendingReview" -> ScoreReviewStatus.PendingReview
            else -> ScoreReviewStatus.PendingReview
        }
    }

    override fun toJson(writer: JsonWriter, value: ScoreReviewStatus?) {
        if (value == null) writer.nullValue() else writer.value(if (value == ScoreReviewStatus.Passed) "passed" else "pendingReview")
    }
}
