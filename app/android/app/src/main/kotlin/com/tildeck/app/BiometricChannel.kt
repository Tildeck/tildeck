package com.tildeck.app

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Biometric unlock on Android (docs/security-model.md, "Biometric unlock"):
 * the vault's biometric key BK is encrypted with AES-256-GCM under a Keystore
 * key that the system releases only after a strong biometric, for every use.
 *
 * Methods of the "tildeck/biometric" channel:
 * - support: "available" or "none".
 * - enroll {vaultId, key, title, subtitle, cancel}: a new Keystore key, then
 *   BK encrypted after a biometric check: {nonce, ciphertext}.
 * - obtain {vaultId, nonce, ciphertext, title, subtitle, cancel}: BK.
 * - remove {vaultId}: deletes the Keystore key.
 * Errors: cancelled (by the user), interrupted (by the system), invalidated,
 * unavailable, failed.
 */
class BiometricChannel(private val activity: FragmentActivity, messenger: BinaryMessenger) {
    private val keyStore: KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    init {
        MethodChannel(messenger, "tildeck/biometric").setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun alias(call: MethodCall) = "tildeck-bio-" + call.argument<String>("vaultId")!!

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "support" -> result.success(if (canAuthenticate()) "available" else "none")
            "enroll" -> enroll(call, result)
            "obtain" -> obtain(call, result)
            "remove" -> {
                try {
                    keyStore.deleteEntry(alias(call))
                } catch (_: Exception) {
                    // Already gone.
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun canAuthenticate() =
        BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS

    private fun enroll(call: MethodCall, result: MethodChannel.Result) {
        if (!canAuthenticate()) return result.error("unavailable", "No strong biometric is set up", null)
        val alias = alias(call)
        val key = call.argument<ByteArray>("key")!!
        val cipher: Cipher
        try {
            keyStore.deleteEntry(alias)
            val secret = newKey(alias)
            cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, secret) }
        } catch (e: Exception) {
            return result.error("failed", e.toString(), null)
        }
        prompt(call, cipher, result) { ready ->
            val ciphertext = ready.doFinal(key)
            mapOf("nonce" to ready.iv, "ciphertext" to ciphertext)
        }
    }

    private fun obtain(call: MethodCall, result: MethodChannel.Result) {
        if (!canAuthenticate()) return result.error("unavailable", "No strong biometric is set up", null)
        val nonce = call.argument<ByteArray>("nonce")!!
        val ciphertext = call.argument<ByteArray>("ciphertext")!!
        val cipher: Cipher
        try {
            val secret = keyStore.getKey(alias(call), null) as SecretKey?
                ?: return result.error("invalidated", "The Keystore key is gone", null)
            cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(TAG_BITS, nonce))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // A biometric was added or removed since biometric unlock was turned on.
            return result.error("invalidated", e.toString(), null)
        } catch (e: Exception) {
            return result.error("failed", e.toString(), null)
        }
        prompt(call, cipher, result) { ready -> ready.doFinal(ciphertext) }
    }

    /** Shows the system's biometric prompt; [use] runs with the released cipher. */
    private fun prompt(call: MethodCall, cipher: Cipher, result: MethodChannel.Result, use: (Cipher) -> Any) {
        var answered = false
        fun answer(block: () -> Unit) {
            if (!answered) {
                answered = true
                block()
            }
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                val ready = auth.cryptoObject?.cipher
                    ?: return answer { result.error("failed", "No cipher came back", null) }
                answer {
                    try {
                        result.success(use(ready))
                    } catch (e: Exception) {
                        result.error("failed", e.toString(), null)
                    }
                }
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                val kind = when (code) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON -> "cancelled"
                    // The system closed it: the app went to the background,
                    // or it was opened before the app came to the front.
                    BiometricPrompt.ERROR_CANCELED -> "interrupted"
                    BiometricPrompt.ERROR_NO_BIOMETRICS,
                    BiometricPrompt.ERROR_HW_NOT_PRESENT,
                    BiometricPrompt.ERROR_HW_UNAVAILABLE,
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "unavailable"
                    else -> "failed"
                }
                answer { result.error(kind, message.toString(), null) }
            }
            // A finger that does not match keeps the prompt open: the system
            // lets the user try again, so nothing is answered here.
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(call.argument<String>("title") ?: "Tildeck")
            .setSubtitle(call.argument<String>("subtitle"))
            .setNegativeButtonText(call.argument<String>("cancel") ?: "Cancel")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    /** A key that needs a strong biometric for every use, in StrongBox when there is one. */
    private fun newKey(alias: String): SecretKey {
        fun spec(strongBox: Boolean): KeyGenParameterSpec {
            val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
            } else {
                // Before Android 11: -1 means every use, with a biometric.
                @Suppress("DEPRECATION")
                builder.setUserAuthenticationValidityDurationSeconds(-1)
            }
            if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) builder.setIsStrongBoxBacked(true)
            return builder.build()
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        return try {
            generator.init(spec(strongBox = true))
            generator.generateKey()
        } catch (e: ProviderException) {
            // StrongBoxUnavailableException (Android 9 and later) is one: no StrongBox here.
            generator.init(spec(strongBox = false))
            generator.generateKey()
        }
    }

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val TAG_BITS = 128
    }
}
