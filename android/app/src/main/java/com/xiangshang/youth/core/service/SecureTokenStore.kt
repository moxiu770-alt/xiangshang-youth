package com.xiangshang.youth.core.service

import android.content.Context
import android.util.Base64
import androidx.core.content.edit
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Stores the remote access token outside ordinary preferences. */
class SecureTokenStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("xiangshang_secure_session", Context.MODE_PRIVATE)
    private val keyAlias = "xiangshang.api-token"
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    init {
        if (!keyStore.containsAlias(keyAlias)) {
            val generator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
            generator.init(android.security.keystore.KeyGenParameterSpec.Builder(
                keyAlias,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT
            ).setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(false)
                .build())
            generator.generateKey()
        }
    }

    fun read(): String? = runCatching {
        val encoded = preferences.getString(KEY_TOKEN, null) ?: return null
        val iv = preferences.getString(KEY_IV, null) ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)))
        String(cipher.doFinal(Base64.decode(encoded, Base64.NO_WRAP)), StandardCharsets.UTF_8)
    }.getOrNull()

    fun write(token: String?) {
        if (token.isNullOrBlank()) {
            preferences.edit {
                remove(KEY_TOKEN)
                remove(KEY_IV)
            }
            return
        }
        runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            preferences.edit {
                putString(KEY_TOKEN, Base64.encodeToString(cipher.doFinal(token.toByteArray(StandardCharsets.UTF_8)), Base64.NO_WRAP))
                putString(KEY_IV, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            }
        }
    }

    private fun secretKey(): SecretKey = (keyStore.getEntry(keyAlias, null) as KeyStore.SecretKeyEntry).secretKey

    private companion object {
        const val KEY_TOKEN = "token"
        const val KEY_IV = "token_iv"
    }
}
