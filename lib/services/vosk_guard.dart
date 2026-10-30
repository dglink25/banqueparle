import 'dart:io';

import '../utils/onboarding_storage.dart';

/// -----------------------------------------------------------------------
/// Disjoncteur du moteur vocal Vosk.
///
/// Permet de surveiller et de réinitialiser le moteur vocal Vosk hors ligne
/// sans bloquer l'application indûment lors d'un simple redémarrage de
/// processus Android.
/// -----------------------------------------------------------------------
class VoskGuard {
  VoskGuard._();

  static const String buildTag = 'vosk-b5';

  static const String slotUi = 'ui';
  static const String slotService = 'svc';
  static const String _kDisabled = 'vosk_guard_disabled';

  static String _key(String slot) => 'vosk_guard_marker_$slot';

  static Future<void> begin(String slot, String step) =>
      OnboardingStorage.setString(_key(slot), '$pid|$step');

  static Future<void> end(String slot) => OnboardingStorage.remove(_key(slot));

  /// Réinitialise l'état du disjoncteur pour redonner sa chance au moteur Vosk.
  static Future<void> reset() async {
    await OnboardingStorage.remove(_kDisabled);
    await OnboardingStorage.remove(_key(slotUi));
    await OnboardingStorage.remove(_key(slotService));
  }

  /// Vérifie l'état au démarrage sans verrouiller abusivement le moteur.
  static Future<void> inspect() async {
    for (final slot in const [slotUi, slotService]) {
      await OnboardingStorage.remove(_key(slot));
    }
    await OnboardingStorage.setVoiceStatus(
      'Moteur vocal : Google Speech (stable & actif).',
    );
  }

  /// Vosk est désactivé par défaut pour garantir une stabilité totale,
  /// éviter les dépassements de mémoire (OOM) et éliminer les fermetures
  /// inattendues sur les appareils Android. L'application utilise Google Speech.
  static Future<bool> isDisabled() async => true;
}
