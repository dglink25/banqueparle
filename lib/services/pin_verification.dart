import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../utils/digit_parser.dart';
import '../utils/onboarding_storage.dart';
import 'voice_dialog.dart';

/// Verifie le code secret de l'utilisateur par comparaison de hachage
/// (jamais le code en clair). Utilise comme repli lorsque l'empreinte
/// digitale echoue ou n'est pas disponible, par exemple avant un
/// virement.
Future<bool> verifyPin({
  required SpeakFn speak,
  required ListenFn listen,
  int maxAttempts = 3,
}) async {
  final storedHash = await OnboardingStorage.getPinHash();
  if (storedHash == null) {
    await speak('Aucun code secret n\'est configuré sur ce compte.');
    return false;
  }

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final raw = await askWithRetry(
      speak: speak,
      listen: listen,
      question: attempt == 1
          ? 'Dites votre code secret à quatre chiffres.'
          : 'Code incorrect. Redites votre code secret à quatre chiffres.',
      maxRetries: 3,
    );
    if (raw == null) return false;

    final digits = extractDigits(raw, maxLength: 4);
    if (digits.length != 4) continue;

    final hash = sha256.convert(utf8.encode(digits)).toString();
    if (hash == storedHash) {
      return true;
    }
  }

  await speak('Trop de tentatives incorrectes.');
  return false;
}
