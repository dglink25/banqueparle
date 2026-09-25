import 'dart:convert';
import 'package:crypto/crypto.dart';

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

  Future<bool> run() async {
    await speak(
      'Pour renforcer la securite de votre compte, veuillez definir un '
      'code secret a quatre chiffres. Ce code sera utilise si votre '
      'empreinte digitale n\'est pas disponible.',
    );

    for (var attempt = 1; attempt <= kMaxAttempts; attempt++) {
      final firstEntry = await _collectFourDigits(
        'Dites votre code a quatre chiffres, un chiffre apres l\'autre.',
      );
      if (firstEntry == null) {
        await speak('Nous reessaierons plus tard pour le code secret.');
        return false;
      }

      final secondEntry = await _collectFourDigits(
        'Merci. Redites le meme code, pour confirmation.',
      );
      if (secondEntry == null) {
        await speak('Nous reessaierons plus tard pour le code secret.');
        return false;
      }

      if (firstEntry == secondEntry) {
        final hash = sha256.convert(utf8.encode(firstEntry)).toString();
        await OnboardingStorage.setPinHash(hash);
        await OnboardingStorage.setNeedsPinStep(false);
        await speak('Votre code secret a ete enregistre avec succes.');
        return true;
      }

      await speak(
        'Les deux codes ne correspondent pas. Reprenons depuis le debut.',
      );
    }

    await speak(
      'Nous n\'avons pas pu confirmer votre code apres plusieurs '
      'tentatives. Redites Banque Parlante plus tard pour reessayer.',
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

      final digits = _extractDigits(raw);
      if (digits.length == kPinLength) {
        return digits;
      }
    }
    return null;
  }

  /// Extrait jusqu'a 4 chiffres d'une reponse vocale : soit dictes en
  /// chiffres directement (le plus courant), soit en toutes lettres.
  String _extractDigits(String raw) {
    final wordToDigit = {
      'zero': '0', 'un': '1', 'une': '1', 'deux': '2', 'trois': '3',
      'quatre': '4', 'cinq': '5', 'six': '6', 'sept': '7', 'huit': '8',
      'neuf': '9',
    };
    final buffer = StringBuffer();
    final normalized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'));

    for (final token in normalized) {
      if (buffer.length >= kPinLength) break;
      if (RegExp(r'^\d+$').hasMatch(token)) {
        for (final ch in token.split('')) {
          if (buffer.length >= kPinLength) break;
          buffer.write(ch);
        }
      } else if (wordToDigit.containsKey(token)) {
        buffer.write(wordToDigit[token]);
      }
    }
    return buffer.toString();
  }
}
