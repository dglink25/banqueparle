import 'dart:io';

import '../utils/onboarding_storage.dart';

/// -----------------------------------------------------------------------
/// Disjoncteur du moteur vocal Vosk.
///
/// Probleme : un plantage NATIF (memoire, bibliotheque, micro) ne peut pas
/// etre intercepte par le code Dart. Si l'etape fautive est rejouee a chaque
/// ouverture, l'application se ferme a chaque fois, indefiniment.
///
/// Principe : avant chaque etape risquee (extraction du modele, chargement,
/// ouverture du micro), on ecrit un marqueur contenant l'identifiant du
/// processus ; on l'efface des que l'etape est terminee. Si, a l'ouverture
/// suivante, un marqueur d'un AUTRE processus est encore la, c'est que le
/// systeme a arrete l'application pendant cette etape : Vosk est alors
/// desactive et l'application retombe sur le moteur Google, au lieu de
/// replanter. L'ecran indique l'etape fautive.
///
/// La désactivation est liée a [buildTag] : une nouvelle version de
/// l'application retente Vosk une fois.
/// -----------------------------------------------------------------------
class VoskGuard {
  VoskGuard._();

  /// A changer a chaque correctif du moteur vocal pour le retenter.
  static const String buildTag = 'vosk-b3';

  static const String slotUi = 'ui';
  static const String slotService = 'svc';
  static const String _kDisabled = 'vosk_guard_disabled';

  static String _key(String slot) => 'vosk_guard_marker_$slot';

  static Future<void> begin(String slot, String step) =>
      OnboardingStorage.setString(_key(slot), '$pid|$step');

  static Future<void> end(String slot) => OnboardingStorage.remove(_key(slot));

  /// A appeler au demarrage (ecran et service). Un marqueur laisse par un
  /// processus different signale un arret brutal pendant une etape.
  static Future<void> inspect() async {
    for (final slot in const [slotUi, slotService]) {
      final marker = await OnboardingStorage.getString(_key(slot));
      if (marker == null) continue;
      final parts = marker.split('|');
      if (parts.first == '$pid') continue; // meme processus : en cours
      final step = parts.length > 1 ? parts[1] : '?';
      await OnboardingStorage.remove(_key(slot));
      await OnboardingStorage.setString(_kDisabled, '$buildTag|$step');
      await OnboardingStorage.setVoiceStatus(
        'Vosk désactivé : le téléphone a arrêté l\'application pendant '
        '« $step ». Moteur de repli : Google.',
      );
    }
  }

  static Future<bool> isDisabled() async {
    final value = await OnboardingStorage.getString(_kDisabled);
    if (value == null) return false;
    return value.split('|').first == buildTag;
  }
}
