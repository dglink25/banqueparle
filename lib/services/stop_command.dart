import '../utils/text_normalize.dart';
import 'voice_dialog.dart';

/// -----------------------------------------------------------------------
/// Commande d'arret d'urgence.
///
/// "Banque Parlante arrete", "Banque Parlante stop", "stop", "arrete",
/// "0", "zero" : coupent l'activite en cours, puis demandent confirmation.
///
/// Precautions pour ne pas declencher l'arret par erreur :
///  - "zero" est un chiffre legitime dans un code PIN ou un numero de
///    compte. L'arret n'est donc declenche que si TOUTE la reponse est
///    une commande d'arret, avec EXACTEMENT UN mot declencheur. Un code
///    dicte "0 0 0 0" contient quatre declencheurs : ce n'est pas un arret.
///  - les seuls autres mots admis sont des mots de politesse ou le nom
///    de l'application ("Banque Parlante", "s'il vous plait"...).
/// -----------------------------------------------------------------------

const Set<String> _triggers = {
  'stop', 'stoppe', 'stoppez', 'stopper',
  'arrete', 'arretes', 'arretez', 'arreter', 'arret',
  'zero', '0', 'urgence',
};

const Set<String> _fillers = {
  'banque', 'parlante', 'parle', 'parlant', 'banc', 'ma',
  's', 'il', 'sil', 'vous', 'plait', 'svp', 'te', 'toi', 'merci',
  'la', 'le', 'maintenant', 'tout', 'de', 'suite',
};

bool isStopCommand(String text) {
  // Apostrophes et tirets deviennent des espaces : "arrete-toi" et
  // "s'il vous plait" doivent donner des mots separes.
  final cleaned = text.replaceAll(RegExp(r"[-'\u2019]"), ' ');
  final words = normalizedWords(cleaned);
  if (words.isEmpty) return false;

  var triggerCount = 0;
  for (final w in words) {
    if (_triggers.contains(w)) {
      triggerCount++;
    } else if (!_fillers.contains(w)) {
      return false;
    }
  }
  return triggerCount == 1;
}

/// Levee par [interceptStop] quand l'utilisateur demande l'arret. Remonte
/// jusqu'a l'appelant, qui demande confirmation puis arrete ou reprend.
class StopRequested implements Exception {
  const StopRequested();
  @override
  String toString() => 'StopRequested';
}

/// Enveloppe une fonction d'ecoute : si la reponse est une commande
/// d'arret, leve [StopRequested] au lieu de la transmettre au parcours en
/// cours (qui la prendrait pour un nom, un montant, etc.).
ListenFn interceptStop(ListenFn inner) => () async {
      final heard = await inner();
      if (heard != null && isStopCommand(heard)) {
        throw const StopRequested();
      }
      return heard;
    };

/// Phrase de confirmation.
const String kStopConfirmQuestion =
    'Vous etes sur de vouloir arreter Banque Parlante ?';

/// Phrase dite une fois l'arret confirme.
const String kStoppedMessage =
    'Banque Parlante est arrete. Pour me relancer, dites "Banque Parlante".';
