package com.xiangshang.youth.core.service

import android.content.Context
import java.io.IOException
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

/** Shared network boundary. Presentation code only talks to repositories. */
sealed class ApiError(message: String) : IOException(message) {
    object NotConfigured : ApiError("服务尚未配置")
    object Unauthorized : ApiError("登录已过期")
    object InvalidResponse : ApiError("服务响应异常")
    class Network(cause: Throwable) : ApiError("网络连接异常") { init { initCause(cause) } }
}

object ApiClient {
    private const val BaseUrl = "https://api.example.com/"
    @Volatile private var token: String? = null
    @Volatile private var secureTokenStore: SecureTokenStore? = null

    private val authInterceptor = Interceptor { chain ->
        val request = chain.request().newBuilder().apply {
            token?.takeIf { it.isNotBlank() }?.let { header("Authorization", "Bearer $it") }
            header("Accept", "application/json")
        }.build()
        chain.proceed(request)
    }

    private val client = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .addInterceptor { chain ->
            try {
                val response = chain.proceed(chain.request())
                if (response.code == 401 || response.code == 403) {
                    response.close()
                    throw ApiError.Unauthorized
                }
                response
            } catch (error: IOException) {
                throw if (error is ApiError) error else ApiError.Network(error)
            }
        }
        .build()
    val retrofit: Retrofit = Retrofit.Builder()
        .baseUrl(BaseUrl)
        .client(client)
        .addConverterFactory(MoshiConverterFactory.create())
        .build()

    fun initialize(context: Context) {
        // Keystore can be temporarily unavailable on a fresh/locked device. The
        // app must still boot in Mock mode instead of crashing before Compose is
        // rendered; a later remote login can retry persistence.
        secureTokenStore = runCatching { SecureTokenStore(context.applicationContext) }.getOrNull()
        token = secureTokenStore?.read()
    }

    fun updateToken(value: String?) {
        token = value?.trim()?.takeIf { it.isNotEmpty() }
        secureTokenStore?.write(token)
    }

    fun clearToken() {
        token = null
        secureTokenStore?.write(null)
    }
    fun hasToken(): Boolean = token != null
}
