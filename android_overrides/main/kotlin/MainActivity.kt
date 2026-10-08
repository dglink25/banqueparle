package com.banqueparle.banqueparle

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// FlutterFragmentActivity (et non FlutterActivity) est OBLIGATOIRE ici :
/// le plugin local_auth affiche l'invite biometrique native (BiometricPrompt)
/// via un DialogFragment, qui necessite une FragmentActivity comme hote.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.banqueparle.banqueparle/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(null)
                    }
                    "callPhone" -> {
                        val number = call.argument<String>("number")
                        if (number.isNullOrBlank()) {
                            result.error("NO_NUMBER", "Numero manquant", null)
                        } else {
                            callPhone(number)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Ouvre, si disponible (Android 14 / API 34 et plus), l'ecran systeme
    /// dedie a l'autorisation des notifications plein ecran pour cette
    /// application. Sur les versions plus anciennes, cette permission est
    /// accordee par defaut et l'ecran n'existe pas : on ouvre alors la
    /// page de details de l'application, qui reste pertinente.
    private fun openFullScreenIntentSettings() {
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            Intent(
                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                Uri.parse("package:$packageName"),
            )
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        try {
            startActivity(intent)
        } catch (e: Exception) {
            val fallback = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
            fallback.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(fallback)
        }
    }

    /// Touche 6 - appel direct du centre de relation client. Si la
    /// permission d'appel a ete accordee, l'appel part immediatement
    /// (ACTION_CALL) : un utilisateur malvoyant n'a rien a valider a
    /// l'ecran. Sinon, le numero est pre-compose dans le composeur
    /// (ACTION_DIAL), qui reste utilisable.
    private fun callPhone(number: String) {
        val granted = checkSelfPermission(Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED
        val action = if (granted) Intent.ACTION_CALL else Intent.ACTION_DIAL
        val intent = Intent(action, Uri.parse("tel:" + Uri.encode(number)))
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }
}
