package com.xiangshang.youth.core.service

import android.content.Context
import com.xiangshang.youth.BuildConfig
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import com.xiangshang.youth.core.model.ScoreReviewStatus
import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.Interceptor
import okhttp3.Authenticator
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import org.json.JSONObject
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

data class ApiEnvelope<T>(val code: String, val message: String, val data: T?)
data class WriteAck(val id: String? = null, val postId: String? = null, val status: String? = null, val version: Int? = null)

/** Shared network boundary. Presentation code only talks to repositories. */
sealed class ApiError(message: String) : IOException(message) {
    object NotConfigured : ApiError("服务尚未配置")
    object Unauthorized : ApiError("登录已过期")
    object Forbidden : ApiError("当前账号无权执行此操作")
    object InvalidResponse : ApiError("服务响应异常")
    class Conflict(message: String) : ApiError(message.ifBlank { "记录已被其他人更新，请刷新后重试" })
    /** The server responded with a model/rules version the app cannot safely render. */
    class ModelContract(message: String) : ApiError(message.ifBlank { "服务数据版本不兼容，请更新应用或联系学校管理员" })
    class Server(val statusCode: Int) : ApiError("服务暂时不可用")
    class Client(message: String) : ApiError(message)
    class Network(cause: Throwable) : ApiError("网络连接异常") { init { initCause(cause) } }
}

object ApiClient {
    @Volatile private var token: String? = null
    @Volatile private var refreshToken: String? = null
    @Volatile private var secureTokenStore: SecureTokenStore? = null

    private val authInterceptor = Interceptor { chain ->
        val request = chain.request().newBuilder().apply {
            token?.takeIf { it.isNotBlank() }?.let { header("Authorization", "Bearer $it") }
            header("Accept", "application/json")
            if (chain.request().method in setOf("POST", "PUT", "PATCH", "DELETE") && chain.request().header("Idempotency-Key") == null) header("Idempotency-Key", java.util.UUID.randomUUID().toString())
        }.build()
        chain.proceed(request)
    }

    private val refreshClient = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).build()
    private val authenticator = object : Authenticator {
        private val lock = Any()
        override fun authenticate(route: Route?, response: Response): Request? {
            if (responseCount(response) > 1) return null
            val failedToken = response.request.header("Authorization")?.removePrefix("Bearer ")
            val latest = token
            if (!latest.isNullOrBlank() && latest != failedToken) return response.request.newBuilder().header("Authorization", "Bearer $latest").build()
            val refresh = refreshToken?.takeIf { it.isNotBlank() } ?: return null
            synchronized(lock) {
                val rotated = token
                if (!rotated.isNullOrBlank() && rotated != failedToken) return response.request.newBuilder().header("Authorization", "Bearer $rotated").build()
                val refreshRequest = Request.Builder()
                    .url(BuildConfig.API_BASE_URL.ensureTrailingSlash() + "v1/auth/refresh")
                    .post(JSONObject(mapOf("refreshToken" to refresh)).toString().toRequestBody("application/json".toMediaType()))
                    .header("Accept", "application/json")
                    .build()
                return runCatching {
                    refreshClient.newCall(refreshRequest).execute().use { refreshResponse ->
                        if (!refreshResponse.isSuccessful) return null
                        val data = JSONObject(refreshResponse.body?.string().orEmpty()).optJSONObject("data") ?: return null
                        val access = data.optString("accessToken").takeIf { it.isNotBlank() } ?: return null
                        val nextRefresh = data.optString("refreshToken").takeIf { it.isNotBlank() } ?: refresh
                        updateSession(access, nextRefresh)
                        response.request.newBuilder().header("Authorization", "Bearer $access").build()
                    }
                }.getOrNull()
            }
        }
        private fun responseCount(response: Response): Int { var count = 1; var prior = response.priorResponse; while (prior != null) { count++; prior = prior.priorResponse }; return count }
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .addInterceptor(authInterceptor)
        .authenticator(authenticator)
        .addInterceptor { chain ->
            try {
                val response = chain.proceed(chain.request())
                if (response.code == 401) {
                    response.close()
                    throw ApiError.Unauthorized
                }
                if (response.code == 403) {
                    response.close()
                    throw ApiError.Forbidden
                }
                if (!response.isSuccessful) {
                    val code = response.code
                    val failure = runCatching { JSONObject(response.body?.string().orEmpty()) }.getOrNull()
                    val failureCode = failure?.optString("code").orEmpty()
                    val message = failure?.optString("message").orEmpty()
                    response.close()
                    throw if (code in 500..599) ApiError.Server(code)
                    else if (failureCode == "VERSION_CONFLICT") ApiError.Conflict(message)
                    else message.takeIf { it.isNotBlank() }?.let(ApiError::Client) ?: ApiError.InvalidResponse
                }
                response
            } catch (error: IOException) {
                throw if (error is ApiError) error else ApiError.Network(error)
            }
        }
        .build()
    val retrofit: Retrofit = Retrofit.Builder()
        .baseUrl(BuildConfig.API_BASE_URL.ensureTrailingSlash())
        .client(client)
        .addConverterFactory(MoshiConverterFactory.create(Moshi.Builder()
            .add(ScoreReviewStatus::class.java, ScoreReviewStatusJsonAdapter())
            .add(KotlinJsonAdapterFactory())
            .build()))
        .build()

    fun initialize(context: Context) {
        // Keystore can be temporarily unavailable on a fresh/locked device. The
        // app must still boot in Mock mode instead of crashing before Compose is
        // rendered; a later remote login can retry persistence.
        secureTokenStore = runCatching { SecureTokenStore(context.applicationContext) }.getOrNull()
        token = secureTokenStore?.read()
        refreshToken = secureTokenStore?.readRefresh()
    }

    fun updateToken(value: String?) {
        token = value?.trim()?.takeIf { it.isNotEmpty() }
        secureTokenStore?.write(token)
    }

    fun updateSession(access: String?, refresh: String?) {
        token = access?.trim()?.takeIf { it.isNotEmpty() }
        refreshToken = refresh?.trim()?.takeIf { it.isNotEmpty() }
        secureTokenStore?.write(token)
        secureTokenStore?.writeRefresh(refreshToken)
    }

    fun clearToken() {
        token = null
        refreshToken = null
        secureTokenStore?.write(null)
        secureTokenStore?.writeRefresh(null)
    }
    fun hasToken(): Boolean = token != null

    private fun String.ensureTrailingSlash(): String = if (endsWith('/')) this else "$this/"
}
