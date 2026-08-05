package com.xiangshang.youth.core.service

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small encrypted SharedPreferences facade for local workflow state. It keeps
 * the existing LocalFeatureStore API while encrypting values with an
 * Android-Keystore AES key. If Keystore is unavailable, it falls back to the
 * old preference representation so Mock mode still boots and can be retried.
 */
class SecurePreferences(context: Context, name: String) {
    private val preferences = context.applicationContext.getSharedPreferences(name, Context.MODE_PRIVATE)
    private val cipher = runCatching { ValueCipher("xiangshang.local-feature-state") }.getOrNull()

    fun getString(key: String, defaultValue: String?): String? {
        val raw = runCatching { preferences.getString(key, null) }.getOrNull() ?: return defaultValue
        return cipher?.decrypt(raw) ?: raw
    }

    fun getStringSet(key: String, defaultValue: Set<String>?): Set<String>? {
        val encrypted = runCatching { preferences.getString(key, null) }.getOrNull()
        if (encrypted != null) {
            cipher?.decrypt(encrypted)?.let { return decodeSet(it) }
        }
        return runCatching { preferences.getStringSet(key, defaultValue) }.getOrDefault(defaultValue)
    }

    fun getBoolean(key: String, defaultValue: Boolean): Boolean {
        val encrypted = runCatching { preferences.getString(key, null) }.getOrNull()
        if (encrypted != null) {
            cipher?.decrypt(encrypted)?.let { return it == "1" || it.equals("true", ignoreCase = true) }
        }
        return runCatching { preferences.getBoolean(key, defaultValue) }.getOrDefault(defaultValue)
    }

    fun edit(): Editor = Editor()

    inner class Editor {
        private val delegate = preferences.edit()

        fun putString(key: String, value: String?): Editor {
            if (value == null) delegate.remove(key)
            else delegate.remove(key).putString(key, encryptOrPlain(value))
            return this
        }

        fun putStringSet(key: String, value: Set<String>?): Editor {
            if (value == null) delegate.remove(key)
            else {
                val encoded = JSONArray(value.toList()).toString()
                val encrypted = runCatching { cipher?.encrypt(encoded) }.getOrNull()
                if (encrypted == null) delegate.remove(key).putStringSet(key, value)
                else delegate.remove(key).putString(key, encrypted)
            }
            return this
        }

        fun putBoolean(key: String, value: Boolean): Editor {
            delegate.remove(key).putString(key, encryptOrPlain(if (value) "1" else "0"))
            return this
        }

        fun remove(key: String): Editor { delegate.remove(key); return this }
        fun clear(): Editor { delegate.clear(); return this }
        fun apply() { delegate.apply() }

        private fun encryptOrPlain(value: String): String = runCatching { cipher?.encrypt(value) }.getOrNull() ?: value
    }

    private fun decodeSet(raw: String): Set<String> = runCatching {
        val array = JSONArray(raw)
        buildSet { repeat(array.length()) { add(array.optString(it)) } }
    }.getOrDefault(emptySet())
}

private class ValueCipher(private val alias: String) {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    init {
        if (!keyStore.containsAlias(alias)) {
            val generator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
            generator.init(android.security.keystore.KeyGenParameterSpec.Builder(
                alias,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT
            ).setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(false)
                .build())
            generator.generateKey()
        }
    }

    fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val payload = cipher.iv + cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    fun decrypt(value: String): String? = runCatching {
        val payload = Base64.decode(value, Base64.NO_WRAP)
        require(payload.size > IV_SIZE)
        val iv = payload.copyOfRange(0, IV_SIZE)
        val encrypted = payload.copyOfRange(IV_SIZE, payload.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        String(cipher.doFinal(encrypted), StandardCharsets.UTF_8)
    }.getOrNull()

    private fun secretKey(): SecretKey = (keyStore.getEntry(alias, null) as KeyStore.SecretKeyEntry).secretKey

    private companion object { const val IV_SIZE = 12 }
}
