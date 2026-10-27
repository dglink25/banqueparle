import '../utils/amount_parser.dart';
import '../utils/date_speech.dart';
import '../utils/onboarding_storage.dart';
import 'auth_gate.dart';
import 'local_cache.dart';
import 'transfer_service.dart';
import 'voice_dialog.dart';

/// Touche 1 - Consulter le solde. Sécurité : biométrie.
///
/// Le solde est lu EN LIGNE, dans la base. Hors connexion, l'application le
/// dit clairement puis donne le dernier solde synchronisé sur le téléphone,
/// avec sa date. Le solde n'est jamais inventé : s'il n'y a ni connexion ni
/// copie locale, elle le dit.
class BalanceFlow {
  final SpeakFn speak;
  final ListenFn listen;

  BalanceFlow({required this.speak, required this.listen});

  Future<void> run() async {
    final gate = AuthGate(speak: speak, listen: listen);
    if (!await gate.biometric('Consulter votre solde')) {
      await speak('Identité non confirmée. Le solde n\'est pas communiqué.');
      return;
    }

    final result = await TransferService.getBalance();

    if (result.ok) {
      final balance = result.value!;
      await LocalCache.saveBalance(balance);
      // Les quatre derniers chiffres du compte permettent de vérifier que
      // c'est bien le compte attendu.
      final account = await OnboardingStorage.getField('account_number');
      final tail = (account != null && account.length >= 4)
          ? ' Compte se terminant par '
              '${account.substring(account.length - 4).split('').join(' ')}.'
          : '';
      await speak('Solde en ligne : ${speakAmount(balance)}.$tail');
      return;
    }

    final intro = result.offline
        ? 'La connexion internet n\'est pas accessible.'
        : (result.message ?? 'La lecture en ligne a échoué.');
    if (result.offline) await LocalCache.setNeedsSync(true);

    final cached = await LocalCache.loadBalance();
    if (cached != null) {
      await speak(
        '$intro Voici votre dernier solde synchronisé, '
        '${describeWhen(cached.at)} : ${speakAmount(cached.value)}.',
      );
    } else {
      await speak(
        '$intro Aucun solde n\'a encore été synchronisé sur ce téléphone.',
      );
    }
  }
}
