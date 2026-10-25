import 'package:local_auth/local_auth.dart';

import 'pin_verification.dart';
import 'voice_dialog.dart';

/// -----------------------------------------------------------------------
/// AuthGate - controle d'identite avant une operation sensible.
///
/// Deux niveaux, conformes a la colonne "Securite requise" du cahier des
/// charges :
///
///  - biometric()  "Biometrie" : empreinte digitale (3 essais). Si le
///    telephone n'a pas de biometrie disponible, ou si l'empreinte
///    echoue, repli sur le code secret, afin qu'une personne dont le
///    doigt est abime ou mouille ne soit pas bloquee hors de son compte.
///
///  - strong()     "Biometrie forte" : double facteur. L'empreinte ET le
///    code secret sont exiges, sans repli. Si le telephone n'a aucune
///    biometrie, seul le code secret peut etre demande et l'utilisateur
///    en est informe.
///
/// Le cahier des charges ne definit pas precisement "forte". Cette
/// interpretation (deux facteurs distincts) est la plus defendable pour
/// une operation qui deplace de l'argent.
/// -----------------------------------------------------------------------
class AuthGate {
  final SpeakFn speak;
  final ListenFn listen;
  final LocalAuthentication _auth = LocalAuthentication();

  static const int kMaxFingerprintAttempts = 3;

  AuthGate({required this.speak, required this.listen});

  Future<bool> biometric(String reason) async {
    if (await _biometricAvailable()) {
      if (await _fingerprint(reason)) return true;
      await speak('Empreinte non validée. Nous passons au code secret.');
    }
    return verifyPin(speak: speak, listen: listen);
  }

  Future<bool> strong(String reason) async {
    if (await _biometricAvailable()) {
      if (!await _fingerprint(reason)) {
        await speak('Empreinte non validée. Opération refusée par sécurité.');
        return false;
      }
    } else {
      await speak(
        'Aucune empreinte n\'est disponible sur ce téléphone. Le code '
        'secret est exige.',
      );
    }
    return verifyPin(speak: speak, listen: listen);
  }

  Future<bool> _biometricAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();
      return supported && canCheck && available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fingerprint(String reason) async {
    for (var attempt = 1; attempt <= kMaxFingerprintAttempts; attempt++) {
      await speak(
        attempt == 1
            ? 'Veuillez poser votre doigt sur le lecteur d\'empreinte.'
            : 'Empreinte non reconnue. Nouvel essai, $attempt sur '
                '$kMaxFingerprintAttempts. Posez votre doigt.',
      );
      try {
        final ok = await _auth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
            useErrorDialogs: true,
          ),
        );
        if (ok) return true;
      } catch (_) {
        // Erreur du lecteur : traitee comme un echec, on retente.
      }
    }
    return false;
  }

  /// Interrompt une invite biometrique en cours (appui sur une autre
  /// touche du pave numerique).
  static Future<void> cancelPrompt() async {
    try {
      await LocalAuthentication().stopAuthentication();
    } catch (_) {}
  }
}
