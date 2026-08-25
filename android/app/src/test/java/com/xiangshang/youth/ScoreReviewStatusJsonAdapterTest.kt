package com.xiangshang.youth

import com.squareup.moshi.JsonReader
import com.xiangshang.youth.core.model.ScoreReviewStatus
import com.xiangshang.youth.core.service.ScoreReviewStatusJsonAdapter
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Test

class ScoreReviewStatusJsonAdapterTest {
    @Test
    fun unknownStatusFailsClosedToPendingReview() {
        val reader = JsonReader.of(Buffer().writeUtf8("\"futureStatus\""))
        assertEquals(ScoreReviewStatus.PendingReview, ScoreReviewStatusJsonAdapter().fromJson(reader))
    }
}
