package com.xiangshang.youth.core.service

import android.content.Context
import com.xiangshang.youth.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.UUID

/**
 * Deterministic, privacy-safe feature rollout. The anonymous installation ID
 * stays in encrypted local storage and is never included in the config call.
 * CI can override values with -PfeatureOverrides=growthInsights=false.
 */
object FeatureRollout {
    enum class Feature(val wireName: String) { GrowthInsights("growthInsights") }
    private data class Rule(val enabled: Boolean, val rolloutPercent: Int)

    private val rules = mutableMapOf(Feature.GrowthInsights.wireName to Rule(enabled = true, rolloutPercent = 100))
    private val _revision = MutableStateFlow(0L)
    val revision: StateFlow<Long> = _revision
    private lateinit var prefs: SecurePreferences
    @Volatile private var initialized = false

    fun initialize(context: Context) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            prefs = SecurePreferences(context.applicationContext, "xiangshang_feature_rollout")
            restore()
            initialized = true
        }
        refresh()
    }

    fun isEnabled(feature: Feature): Boolean {
        if (!initialized) return true // Maintain the bundled safe default until initialization completes.
        parseOverrides()[feature.wireName]?.let { return it }
        val rule = synchronized(rules) { rules[feature.wireName] } ?: return false
        return rule.enabled && stableBucket(feature.wireName) < rule.rolloutPercent.coerceIn(0, 100)
    }

    private fun refresh() {
        val endpoint = BuildConfig.ROLLOUT_CONFIG_URL.trim()
        if (endpoint.isBlank() || !endpoint.startsWith("https://")) return
        Thread {
            runCatching {
                val response = OkHttpClient().newCall(Request.Builder().url(endpoint).get().build()).execute()
                response.use {
                    if (!it.isSuccessful) return@runCatching
                    val raw = it.body?.string().orEmpty()
                    val root = JSONObject(raw)
                    val features = root.optJSONArray("features") ?: return@runCatching
                    val loaded = mutableMapOf<String, Rule>()
                    repeat(features.length()) { index ->
                        val item = features.optJSONObject(index) ?: return@repeat
                        val key = item.optString("key")
                        if (key.isNotBlank()) loaded[key] = Rule(item.optBoolean("enabled", true), item.optInt("rolloutPercent", 100).coerceIn(0, 100))
                    }
                    if (loaded.isNotEmpty()) {
                        synchronized(rules) { rules.putAll(loaded) }
                        prefs.edit().putString("payload", raw).apply()
                        _revision.value += 1
                    }
                }
            }
        }.start()
    }

    private fun restore() {
        val raw = prefs.getString("payload", null) ?: return
        runCatching {
            val features = JSONObject(raw).optJSONArray("features") ?: return@runCatching
            repeat(features.length()) { index ->
                val item = features.optJSONObject(index) ?: return@repeat
                val key = item.optString("key")
                if (key.isNotBlank()) rules[key] = Rule(item.optBoolean("enabled", true), item.optInt("rolloutPercent", 100).coerceIn(0, 100))
            }
            _revision.value += 1
        }
    }

    private fun stableBucket(feature: String): Int {
        val identifier = prefs.getString("installation_id", null) ?: UUID.randomUUID().toString().lowercase().also {
            prefs.edit().putString("installation_id", it).apply()
        }
        var hash = 1_469_598_103_934_665_603UL
        ("$identifier|$feature").encodeToByteArray().forEach { byte -> hash = (hash xor byte.toUByte().toULong()) * 1_099_511_628_211UL }
        return (hash % 100UL).toInt()
    }

    private fun parseOverrides(): Map<String, Boolean> = BuildConfig.FEATURE_OVERRIDES
        .split(',')
        .mapNotNull { token -> token.split('=', limit = 2).takeIf { it.size == 2 } }
        .mapNotNull { (key, value) -> value.trim().lowercase().let { normalized -> when (normalized) { "true", "1" -> key.trim() to true; "false", "0" -> key.trim() to false; else -> null } } }
        .toMap()
}
