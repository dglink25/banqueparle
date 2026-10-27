import '../utils/text_normalize.dart';

/// Les huit commandes du cahier des charges (section 3.1).
///
/// Chaque commande est accessible par la voix (mot-cle d'intention) ou
/// par la touche correspondante du pave numerique de secours. Une seule
/// table (ci-dessous) sert aux deux, pour qu'elles ne divergent jamais.
enum BankIntent {
  balance, // touche 1
  history, // touche 2
  transfer, // touche 3
  otp, // touche 4
  profile, // touche 5
  advisor, // touche 6
  quit, // touche 0
  none,
}

class KeyDef {
  final String key;
  final BankIntent intent;
  final String label;
  const KeyDef(this.key, this.intent, this.label);
}

/// Disposition du pave numerique de secours.
const List<KeyDef> kKeypad = [
  KeyDef('1', BankIntent.balance, 'Solde'),
  KeyDef('2', BankIntent.history, 'Historique'),
  KeyDef('3', BankIntent.transfer, 'Virement'),
  KeyDef('4', BankIntent.otp, 'Code OTP'),
  KeyDef('5', BankIntent.profile, 'Profil'),
  KeyDef('6', BankIntent.advisor, 'Conseiller'),
  KeyDef('0', BankIntent.quit, 'Arrêter'),
];

BankIntent intentForKey(String key) {
  for (final k in kKeypad) {
    if (k.key == key) return k.intent;
  }
  return BankIntent.none;
}

/// Question posee apres le mot-cle. Volontairement tres courte : pour un
/// utilisateur malvoyant, un long menu parle avant de pouvoir repondre est
/// fatigant. Les options ne sont detaillees qu'en l'absence de reponse.
const String kMenuQuestion = 'Que souhaitez-vous faire ?';

/// Relance courte, si la premiere question du menu n'a recu aucune reponse.
const String kMenuRetryQuestion =
    'Dites : solde, historique, virement, code de sécurité, profil, '
    'conseiller, ou stop. Vous pouvez aussi dire un numéro de 1 à 6.';

/// Libelle annonce a l'utilisateur pour lui confirmer ce qui a ete compris.
String intentLabel(BankIntent intent) {
  switch (intent) {
    case BankIntent.balance:
      return 'consulter le solde';
    case BankIntent.history:
      return 'l\'historique des opérations';
    case BankIntent.transfer:
      return 'effectuer un virement';
    case BankIntent.otp:
      return 'le code de sécurité';
    case BankIntent.profile:
      return 'la gestion du profil';
    case BankIntent.advisor:
      return 'contacter un conseiller';
    case BankIntent.quit:
      return 'arrêter Banque Parlante';
    case BankIntent.none:
      return '';
  }
}

/// Retire le nom de l'application d'une phrase reconnue, pour isoler la
/// demande : "Banque Parlante solde" devient "solde". Permet de dire la
/// demande dans la meme phrase que le mot-cle, comme l'application
/// l'annonce a l'enrolement.
String stripWakeWord(String recognized) {
  var norm = normalizeText(recognized.replaceAll(RegExp(r"[-'\u2019]"), ' '));
  const variants = [
    'ma banque parlante', 'banque parlante', 'banc parlant',
    'banque parlant', 'banc parlante', 'banque parle',
  ];
  for (final v in variants) {
    norm = norm.replaceAll(v, ' ');
  }
  return norm.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _history = {
  'historique', 'operations', 'operation', 'mouvements', 'mouvement',
  'releve', 'dernier', 'derniere', 'derniers', 'dernieres',
};
const _transfer = {
  'virement', 'virements', 'transfert', 'transferts', 'transferer',
  'envoyer', 'envoi', 'verser', 'versement',
};
const _balance = {'solde', 'combien', 'reste'};
const _advisor = {
  'conseiller', 'conseillere', 'appeler', 'contacter', 'humain', 'agence',
};
const _quit = {
  'quitter', 'quitte', 'fermer', 'sortir', 'arreter', 'arrete', 'arret',
  'stop', 'stoppe', 'stopper', 'revoir', 'termine', 'urgence',
};
const _profile = {
  'profil', 'parametres', 'parametre', 'coordonnees', 'informations',
  'modifier', 'changer',
};
const _otp = {'otp', 'code', 'temporaire'};

const _digitWords = {
  '0': '0', 'zero': '0',
  '1': '1', 'un': '1', 'une': '1',
  '2': '2', 'deux': '2',
  '3': '3', 'trois': '3',
  '4': '4', 'quatre': '4',
  '5': '5', 'cinq': '5',
  '6': '6', 'six': '6',
};

/// Mots qu'un accent produit a la place de "un" et "deux" quand le chiffre
/// est dit seul. Ils figurent aussi dans les grammaires (grammars.dart).
const _aloneDigit = {
  'hein': '1', 'in': '1', 'ain': '1', 'en': '1',
  'de': '2', 'des': '2', 'deu': '2', 'deus': '2', 'dos': '2',
};

/// Determine l'intention a partir de la phrase reconnue. Comparaison mot
/// a mot (et non par sous-chaine) pour eviter les faux positifs.
///
/// L'ordre compte : "dernier virement" doit donner l'historique et non un
/// nouveau virement, et "changer mon code secret" doit donner le profil et
/// non un code a usage unique. Les chiffres isoles ("trois") ne sont
/// consideres qu'en dernier, quand aucun mot-cle n'a correspondu.
BankIntent detectIntent(String recognized) {
  final list = normalizedWords(recognized);
  final words = list.toSet();
  bool any(Set<String> s) => words.any(s.contains);

  if (any(_history)) return BankIntent.history;
  if (any(_transfer)) return BankIntent.transfer;
  if (any(_balance)) return BankIntent.balance;
  if (any(_advisor)) return BankIntent.advisor;
  if (any(_quit)) return BankIntent.quit;
  if (any(_profile)) return BankIntent.profile;
  if (any(_otp)) return BankIntent.otp;

  for (final w in list) {
    final key = _digitWords[w];
    if (key != null) return intentForKey(key);
  }

  // Approximations d'un chiffre dit seul ("hein" pour un, "de" pour deux) :
  // acceptees uniquement quand elles constituent toute la reponse.
  if (list.length == 1) {
    final key = _aloneDigit[list.first];
    if (key != null) return intentForKey(key);
  }
  return BankIntent.none;
}
