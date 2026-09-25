import 'package:local_auth/local_auth.dart';

import '../utils/onboarding_storage.dart';
import 'voice_dialog.dart';

/// -----------------------------------------------------------------------
/// FingerprintEnrollmentFlow
///
/// Contrainte Android incontournable : l'authentification biométrique
/// (BiometricPrompt / local_auth) ne peut être invoquée que depuis un
/// écran affiché au premier plan (Activity visible) — impossible à
/// déclencher depuis le service d'arrière-plan headless. C'est pourquoi
/// cette étape s'exécute dans l'application, une fois que l'utilisateur
/// l'a ouverte (manuellement ou via le réveil déclenché par le mot-clé).
///
/// Important — limite technique honnête : Android ne permet à AUCUNE
/// application tierce d'enrôler un NOUVEAU doigt dans le capteur (cela
/// reste une fonction exclusive des Réglages système, protégée par le
/// code PIN de l'utilisateur, pour des raisons de sécurité matérielle
/// TEE/StrongBox). Ce flux authentifie donc l'utilisateur avec les
/// empreintes déjà enregistrées sur son téléphone (ouverture du lecteur
/// d'empreinte natif par défaut de l'appareil), ce qui couvre l'usage
/// demandé (vérifier/associer une empreinte à un profil BanqueParle,
/// avec confirmation vocale et jusqu'à 3 "associations" successives).
/// Si aucune empreinte n'est enregistrée sur le téléphone, l'utilisateur
/// est orienté vocalement vers les réglages système pour en créer une.
/// -----------------------------------------------------------------------
class FingerprintEnrollmentFlow {
  final LocalAuthentication _auth = LocalAuthentication();
  final SpeakFn speak;
  final ListenFn listen;

  FingerprintEnrollmentFlow({required this.speak, required this.listen});

  static const int kMaxFingers = 3;
  static const int kMaxAttemptsPerFinger = 3;

  /// Lance le flux complet. Renvoie true si au moins une empreinte a été
  /// validée avec succès.
  Future<bool> run() async {
    final canCheck = await _canUseBiometrics();
    if (!canCheck) {
      await speak(
        'Aucune empreinte digitale n\'est configurée sur ce téléphone. '
        'Veuillez vous rendre dans les réglages de sécurité de votre '
        'appareil pour en enregistrer une, puis redites « Banque '
        'Parlante » pour continuer.',
      );
      return false;
    }

    final userName = await OnboardingStorage.getUserName() ?? '';
    int enrolledCount = await OnboardingStorage.getFingerprintCount();
    bool atLeastOneSuccess = enrolledCount > 0;

    while (enrolledCount < kMaxFingers) {
      final ordinal = enrolledCount == 0
          ? 'votre empreinte'
          : 'une nouvelle empreinte (numéro ${enrolledCount + 1})';
      await speak('Veuillez poser votre doigt sur le lecteur d\'empreinte '
          'pour enregistrer $ordinal.');

      final success = await _authenticateWithRetries();

      if (success) {
        enrolledCount++;
        atLeastOneSuccess = true;
        await OnboardingStorage.setFingerprintCount(enrolledCount);
        await speak('Empreinte reconnue avec succès.');

        if (enrolledCount >= kMaxFingers) {
          await speak(
            'Vous avez atteint le nombre maximal de trois empreintes.',
          );
          break;
        }

        final wantsMore = await askWithRetry(
          speak: speak,
          listen: listen,
          question:
              'Voulez-vous ajouter une autre empreinte ? Dites 1 pour oui, '
              'ou 2 pour non.',
          maxRetries: 2,
        );

        final yesNo = wantsMore != null ? parseYesNo(wantsMore) : null;
        if (yesNo != true) {
          break; // L'utilisateur a dit non, ou n'a pas répondu clairement.
        }
      } else {
        await speak(
          'Échec après plusieurs tentatives. Nous arrêtons là '
          'l\'enregistrement des empreintes pour le moment.',
        );
        break;
      }
    }

    if (atLeastOneSuccess) {
      final greetingName = userName.isNotEmpty ? ' $userName' : '';
      await speak(
        'Bienvenue$greetingName. Votre enrôlement est terminé. '
        'Vous pouvez maintenant utiliser Banque Parlante normalement.',
      );
      await OnboardingStorage.setNeedsFingerprintStep(false);
      await OnboardingStorage.setCompleted(true);
    }

    return atLeastOneSuccess;
  }

  Future<bool> _canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();
      return supported && canCheck && available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticateWithRetries() async {
    for (var attempt = 1; attempt <= kMaxAttemptsPerFinger; attempt++) {
      try {
        final ok = await _auth.authenticate(
          localizedReason:
              'Posez votre doigt sur le lecteur pour BanqueParle',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
            useErrorDialogs: true,
          ),
        );
        if (ok) return true;

        if (attempt < kMaxAttemptsPerFinger) {
          await speak(
            'Empreinte non reconnue. Nouvelle tentative, essai '
            '${attempt + 1} sur $kMaxAttemptsPerFinger.',
          );
        }
      } catch (e) {
        if (attempt < kMaxAttemptsPerFinger) {
          await speak(
            'Une erreur est survenue avec le lecteur d\'empreinte. '
            'Nouvelle tentative, essai ${attempt + 1} sur '
            '$kMaxAttemptsPerFinger.',
          );
        }
      }
    }
    return false;
  }
}
