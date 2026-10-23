import '../utils/amount_parser.dart';
import '../utils/digit_parser.dart';
import 'auth_gate.dart';
import 'transfer_service.dart';
import 'voice_dialog.dart';

/// -----------------------------------------------------------------------
/// TransferFlow - touche 3, "Effectuer un virement", securite : biometrie
/// forte.
///
/// Collecte le destinataire et le montant a la voix, avec confirmation
/// orale de chaque valeur (une erreur de reconnaissance non confirmee
/// enverrait de l'argent au mauvais compte ou pour le mauvais montant).
/// Exige ensuite une identite forte (empreinte ET code secret) avant
/// d'executer le virement.
/// -----------------------------------------------------------------------
class TransferFlow {
  final SpeakFn speak;
  final ListenFn listen;

  TransferFlow({required this.speak, required this.listen});

  Future<void> run() async {
    final toAccount = await _collectAccountNumber();
    if (toAccount == null) return _cancelled();

    final amount = await _collectAmount();
    if (amount == null) return _cancelled();

    // Une reponse non comprise n'est JAMAIS prise pour un "oui" : apres
    // plusieurs essais sans reponse claire, le virement est annule.
    final confirmed = await askYesNo(
      speak: speak,
      listen: listen,
      question: 'Vous allez envoyer ${speakAmount(amount)} vers le compte '
          '${_spellDigits(toAccount)}. Confirmez-vous ce virement ?',
      maxAttempts: 3,
      strictYes: true,
    );
    if (confirmed != true) {
      await speak('Virement annule.');
      return;
    }

    final gate = AuthGate(speak: speak, listen: listen);
    final authenticated = await gate.strong('Confirmez le virement');
    if (!authenticated) {
      await speak(
        'Identite non confirmee. Le virement n\'a pas ete effectue, par '
        'securite.',
      );
      return;
    }

    await speak('Virement en cours.');
    final result = await TransferService.transfer(
      toAccount: toAccount,
      amount: amount,
    );

    if (result.success) {
      final balanceText = result.newBalance != null
          ? ' Votre nouveau solde est de ${speakAmount(result.newBalance!)}.'
          : '';
      await speak('${result.message}$balanceText');
    } else {
      await speak(result.message);
    }
  }

  Future<void> _cancelled() => speak(
        'Nous annulons le virement. Redites "Banque Parlante" pour '
        'recommencer.',
      );

  /// Epelle un numero chiffre par chiffre pour la synthese vocale, afin
  /// qu'il ne soit pas lu comme un tres grand nombre.
  String _spellDigits(String value) => value.split('').join(' ');

  Future<String?> _collectAccountNumber() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final raw = await askWithRetry(
        speak: speak,
        listen: listen,
        question: 'Quel est le numero de compte du destinataire ?',
        maxRetries: 3,
      );
      if (raw == null) return null;

      var candidate = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (candidate.isEmpty) {
        // Chiffres dictes en toutes lettres ("un deux trois...").
        candidate = extractDigits(raw, maxLength: 24);
      }
      if (candidate.isEmpty) {
        await speak('Je n\'ai pas compris ce numero de compte.');
        continue;
      }

      final ok = await askYesNo(
        speak: speak,
        listen: listen,
        question: 'Vous avez dit le compte ${_spellDigits(candidate)}. '
            'Est-ce correct ?',
        strictYes: true,
      );
      if (ok == true) return candidate;
    }
    return null;
  }

  Future<double?> _collectAmount() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final raw = await askWithRetry(
        speak: speak,
        listen: listen,
        question: 'Quel montant souhaitez-vous transferer ?',
        maxRetries: 3,
      );
      if (raw == null) return null;

      final amount = parseAmount(raw);
      if (amount == null) {
        await speak('Je n\'ai pas compris le montant. Dites-le en chiffres.');
        continue;
      }

      final ok = await askYesNo(
        speak: speak,
        listen: listen,
        question: 'Vous avez dit ${speakAmount(amount)}. Est-ce correct ?',
        strictYes: true,
      );
      if (ok == true) return amount;
    }
    return null;
  }
}
