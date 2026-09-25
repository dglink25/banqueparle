import 'package:permission_handler/permission_handler.dart';

/// Demande toutes les permissions nécessaires au fonctionnement du
/// mot-clé en arrière-plan :
///  - Microphone (obligatoire)
///  - Notifications (obligatoire pour réveiller l'app, Android 13+)
///  - Ignorer l'optimisation de batterie (recommandé, sinon Android peut
///    tuer le service d'écoute après quelques minutes)
class PermissionsHelper {
  static Future<bool> requestAll() async {
    final statuses = await [
      Permission.microphone,
      Permission.notification,
    ].request();

    final micOk = statuses[Permission.microphone]?.isGranted ?? false;

    // Demande séparée : ignorer l'optimisation batterie (Android uniquement,
    // non bloquant si refusé, mais fortement recommandé).
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return micOk;
  }

  static Future<bool> hasMicrophonePermission() async {
    return Permission.microphone.isGranted;
  }
}
