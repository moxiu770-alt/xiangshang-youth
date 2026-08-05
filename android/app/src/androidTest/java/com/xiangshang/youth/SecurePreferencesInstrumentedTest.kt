package com.xiangshang.youth

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.xiangshang.youth.core.service.SecurePreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class SecurePreferencesInstrumentedTest {
    @Test
    fun localWorkflowValuesRoundTripAndClear() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "secure-test-${UUID.randomUUID()}"
        val preferences = SecurePreferences(context, name)
        preferences.edit()
            .putString("draft", "孩子运动记录")
            .putStringSet("children", setOf("s01", "s02"))
            .putBoolean("notifications", true)
            .apply()

        assertEquals("孩子运动记录", preferences.getString("draft", null))
        assertEquals(setOf("s01", "s02"), preferences.getStringSet("children", emptySet()))
        assertTrue(preferences.getBoolean("notifications", false))

        preferences.edit().clear().apply()
        assertEquals(null, preferences.getString("draft", null))
    }
}
