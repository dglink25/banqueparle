import '../utils/amount_parser.dart';
import 'auth_gate.dart';
import 'transfer_service.dart';
import 'voice_dialog.dart';

/// Touche 2 - Historique des operations. Securite : biometrie.
/// Enumere vocalement les dernieres operations, la plus recente d'abord.
/// Les operations du modele sont les virements emis et recus ; un
/// prelevement est un debit comme un autre, il apparait comme virement
/// emis.
class HistoryFlow {
  final SpeakFn speak;
  final ListenFn listen;

  HistoryFlow({required this.speak, required this.listen});

  static const _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  static const _ordinals = ['La plus récente', 'Ensuite', 'Puis'];

  Future<void> run() async {
    final gate = AuthGate(speak: speak, listen: listen);
    if (!await gate.biometric('Consulter votre historique')) {
      await speak('Identité non confirmée. L\'historique n\'est pas communiqué.');
      return;
    }

    final entries = await TransferService.getHistory(limit: 3);
    if (entries == null) {
      await speak(
        'Impossible de lire votre historique. Vérifiez votre connexion '
        'internet, puis réessayez.',
      );
      return;
    }
    if (entries.isEmpty) {
      await speak('Vous n\'avez aucune opération enregistrée.');
      return;
    }

    await speak(
      entries.length == 1
          ? 'Vous avez une opération.'
          : 'Voici vos ${entries.length} dernières opérations.',
    );

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final d = e.date.toLocal();
      final when = '${d.day} ${_months[d.month - 1]}';
      final direction = e.sent
          ? 'Virement envoyé de ${speakAmount(e.amount)} à ${e.otherName}'
          : 'Virement reçu de ${speakAmount(e.amount)} de ${e.otherName}';
      final last4 = e.otherAccount.length > 4
          ? e.otherAccount.substring(e.otherAccount.length - 4)
          : e.otherAccount;
      await speak(
        '${_ordinals[i]} : $direction, compte se terminant par '
        '${last4.split('').join(' ')}, le $when.',
      );
    }
  }
}
