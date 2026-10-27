import '../utils/amount_parser.dart';
import '../utils/date_speech.dart';
import 'auth_gate.dart';
import 'local_cache.dart';
import 'transfer_service.dart';
import 'voice_dialog.dart';

/// Touche 2 - Historique des opérations. Sécurité : biométrie.
///
/// Lu EN LIGNE ; hors connexion, l'application le dit puis énumère la
/// dernière copie synchronisée, avec sa date. Les opérations du modèle sont
/// les virements émis et reçus ; un prélèvement est un débit comme un autre,
/// il apparaît comme virement envoyé.
class HistoryFlow {
  final SpeakFn speak;
  final ListenFn listen;

  HistoryFlow({required this.speak, required this.listen});

  static const _ordinals = ['La plus récente', 'Ensuite', 'Puis'];
  static const int _spoken = 3; // opérations énoncées
  static const int _synced = 10; // opérations conservées en copie locale

  Future<void> run() async {
    final gate = AuthGate(speak: speak, listen: listen);
    if (!await gate.biometric('Consulter votre historique')) {
      await speak(
        'Identité non confirmée. L\'historique n\'est pas communiqué.',
      );
      return;
    }

    final result = await TransferService.getHistory(limit: _synced);

    if (result.ok) {
      final entries = result.value!;
      await LocalCache.saveHistory(entries);
      if (entries.isEmpty) {
        await speak('Historique en ligne : vous n\'avez aucune opération.');
        return;
      }
      await speak('Historique en ligne.');
      await _enumerate(entries);
      return;
    }

    final intro = result.offline
        ? 'La connexion internet n\'est pas accessible.'
        : (result.message ?? 'La lecture en ligne a échoué.');
    if (result.offline) await LocalCache.setNeedsSync(true);

    final cached = await LocalCache.loadHistory();
    if (cached == null) {
      await speak(
        '$intro Aucun historique n\'a encore été synchronisé sur ce '
        'téléphone.',
      );
      return;
    }
    if (cached.value.isEmpty) {
      await speak(
        '$intro Dernière synchronisation ${describeWhen(cached.at)} : aucune '
        'opération.',
      );
      return;
    }
    await speak(
      '$intro Voici vos dernières opérations synchronisées, '
      '${describeWhen(cached.at)}.',
    );
    await _enumerate(cached.value);
  }

  Future<void> _enumerate(List<HistoryEntry> all) async {
    final entries = all.take(_spoken).toList();
    await speak(
      entries.length == 1
          ? 'Vous avez une opération.'
          : 'Voici vos ${entries.length} dernières opérations.',
    );

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final direction = e.sent
          ? 'Virement envoyé de ${speakAmount(e.amount)} à ${e.otherName}'
          : 'Virement reçu de ${speakAmount(e.amount)} de ${e.otherName}';
      final last4 = e.otherAccount.length > 4
          ? e.otherAccount.substring(e.otherAccount.length - 4)
          : e.otherAccount;
      await speak(
        '${_ordinals[i]} : $direction, compte se terminant par '
        '${last4.split('').join(' ')}, ${describeWhen(e.date)}.',
      );
    }
  }
}
