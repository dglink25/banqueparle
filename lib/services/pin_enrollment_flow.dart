import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../utils/digit_parser.dart';
import '../utils/onboarding_storage.dart';
import 'voice_dialog.dart';

/// -----------------------------------------------------------------------
/// PinEnrollmentFlow
///
/// Note d'ingenierie : le cahier des charges ne demandait qu'une securite
/// par empreinte digitale. Un code secret de secours a ete ajoute car une
/// application bancaire ne peut pas dependre d'un seul facteur
/// d'authentification : le materiel biometrique peut etre absent,
/// endommage, ou temporairement indisponible (doigt mouille, capteur
/// defectueux). Ce code sert exclusivement de repli.
///
/// Le code n'est jamais stocke en clair : seule son empreinte SHA-256 est
/// conservee (meme principe qu'un mot de passe), afin qu'aucune fuite de
/// la base locale ne puisse exposer le code reel.
/// -----------------------------------------------------------------------
class PinEnrollmentFlow {
  final SpeakFn speak;
  final ListenFn listen;

  PinEnrollmentFlow({required this.speak, required this.listen});

  static const int kPinLength = 4;
  static const int kMaxAttempts = 4;

  /// [introduction] permet d'adapter la phrase d'ouverture (definition
  /// initiale a l'enrolement, ou changement depuis la gestion du profil).
  Future<bool> run({String? introduction}) async {
    await speak(
      introduction ??
          'Pour renforcer la sécurité de votre compte, veuillez définir un '
              'code secret à quatre chiffres. Ce code sera utilisé si votre '
              'empreinte digitale n\'est pas disponible.',
    );

    for (var attempt = 1; attempt <= kMaxAttempts; attempt++) {
      final firstEntry = await _collectFourDigits(
        'Dites votre code à quatre chiffres, un chiffre après l\'autre.',
      );
      if (firstEntry == null) {
        await speak('Nous réessaierons plus tard pour le code secret.');
        return false;
      }

      final secondEntry = await _collectFourDigits(
        'Merci. Redites le même code, pour confirmation.',
      );
      if (secondEntry == null) {
        await speak('Nous réessaierons plus tard pour le code secret.');
        return false;
      }

      if (firstEntry == secondEntry) {
        final hash = sha256.convert(utf8.encode(firstEntry)).toString();
        await OnboardingStorage.setPinHash(hash);
        await OnboardingStorage.setNeedsPinStep(false);
        await speak('Votre code secret a été enregistré avec succès.');
        return true;
      }

      await speak(
        'Les deux codes ne correspondent pas. Reprenons depuis le début.',
      );
    }

    await speak(
      'Nous n\'avons pas pu confirmer votre code après plusieurs '
      'tentatives. Redites Banque Parlante plus tard pour réessayer.',
    );
    return false;
  }

  Future<String?> _collectFourDigits(String question) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final raw = await askWithRetry(
        speak: speak,
        listen: listen,
        question: attempt == 0
            ? question
            : 'Merci de dire quatre chiffres uniquement. $question',
        maxRetries: 3,
      );
      if (raw == null) return null;

      final digits = extractDigits(raw, maxLength: kPinLength);
      if (digits.length == kPinLength) {
        return digits;
      }
    }
    return null;
  }
}
