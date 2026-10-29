import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Demande toutes les permissions nécessaires au fonctionnement du
/// mot-clé en arrière-plan :
///  - Microphone (obligatoire)
///  - Notifications (obligatoire pour réveiller l'app, Android 13+)
///  - Téléphone (appel direct du conseiller, optionnel)
///  - Ignorer l'optimisation de batterie (recommandé, sinon Android peut
///    tuer le service d'écoute après quelques minutes)
class PermissionsHelper {
  static Future<bool> requestAll() async {
    bool micOk = false;
    try {
      final statuses = await [
        Permission.microphone,
        Permission.notification,
        // Appel direct du conseiller (touche 6). Non bloquant : en cas de
        // refus, le numero est simplement pre-compose dans le composeur.
        Permission.phone,
      ].request();

      micOk = statuses[Permission.microphone]?.isGranted ?? false;
    } catch (e) {
      debugPrint('[PermissionsHelper] Erreur demande permissions de base: $e');
    }

    // Demande séparée : ignorer l'optimisation batterie (Android uniquement,
    // non bloquant si refusé, mais fortement recommandé pour l'écoute continue).
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('[PermissionsHelper] Ignorer optimisation batterie non supporté: $e');
    }

    return micOk;
  }

  static Future<bool> hasMicrophonePermission() async {
    try {
      return await Permission.microphone.isGranted;
    } catch (_) {
      return false;
    }
  }
}

