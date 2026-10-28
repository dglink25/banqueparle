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
  'historique', 'historiques', 'operations', 'operation', 'mouvements', 'mouvement',
  'releve', 'releves', 'transactions', 'transaction', 'dernier', 'derniere',
  'derniers', 'dernieres',
};

const _transfer = {
  'virement', 'virements', 'transfert', 'transferts', 'transferer',
  'envoyer', 'envoi', 'verser', 'versement', 'virer', 'payer',
};

const _balance = {
  'solde', 'soldes', 'argent', 'montant', 'avoir', 'balance', 'disponible',
  'combien', 'reste',
};

const _advisor = {
  'conseiller', 'conseillere', 'appeler', 'contacter', 'humain', 'agence',
  'assistance', 'aide', 'support',
};

const _quit = {
  'quitter', 'quitte', 'fermer', 'sortir', 'arreter', 'arrete', 'arret',
  'stop', 'stoppe', 'stopper', 'revoir', 'aurevoir', 'termine', 'urgence',
  'annuler', 'annule', 'fin',
};

const _profile = {
  'profil', 'profils', 'parametres', 'parametre', 'coordonnees', 'informations',
  'modifier', 'changer', 'infos',
};

const _otp = {'otp', 'code', 'temporaire', 'securite', 'token', 'pass'};

const _digitWords = {
  '0': '0', 'zero': '0',
  '1': '1', 'un': '1', 'une': '1', 'premier': '1', 'premiere': '1', '1er': '1', '1re': '1',
  '2': '2', 'deux': '2', 'second': '2', 'seconde': '2', 'deuxieme': '2', '2e': '2', '2eme': '2',
  '3': '3', 'trois': '3', 'troisieme': '3', '3e': '3', '3eme': '3',
  '4': '4', 'quatre': '4', 'quatrieme': '4', '4e': '4', '4eme': '4',
  '5': '5', 'cinq': '5', 'cinquieme': '5', '5e': '5', '5eme': '5',
  '6': '6', 'six': '6', 'sixieme': '6', '6e': '6', '6eme': '6',
};

const _aloneDigit = {
  'hein': '1', 'in': '1', 'ain': '1', 'en': '1',
  'de': '2', 'des': '2', 'deu': '2', 'deus': '2', 'dos': '2',
};

/// Determine l'intention a partir de la phrase reconnue.
///
/// L'ordre d'apparition des mots dans la phrase est pris en compte pour
/// eviter qu'un echo vocal (ex: "solde avec s virement...") ne declenche
/// un virement au lieu du solde demande.
BankIntent detectIntent(String recognized) {
  final list = normalizedWords(recognized);
  if (list.isEmpty) return BankIntent.none;

  final words = list.toSet();

  // 1. Commande d'arrêt / quitter prioritaire
  if (words.any(_quit.contains)) {
    return BankIntent.quit;
  }

  // 2. Chiffre isolé ou désignation par touche ("1", "choix 1", "touche 2", "premier", etc.)
  for (var i = 0; i < list.length; i++) {
    final w = list[i];
    final key = _digitWords[w];
    if (key != null) {
      // Si la phrase est courte (<= 3 mots, ex: "touche 1", "le 2"), le chiffre est l'intention directe
      if (list.length <= 3) {
        return intentForKey(key);
      }
    }
  }

  if (list.length == 1) {
    final key = _aloneDigit[list.first];
    if (key != null) return intentForKey(key);
  }

  // 3. Recherche des mots-clés bancaires selon leur ordre d'apparition dans la phrase
  BankIntent firstFound = BankIntent.none;
  int firstIndex = 999999;

  void checkCategory(Set<String> category, BankIntent intent) {
    for (var i = 0; i < list.length; i++) {
      if (category.contains(list[i]) && i < firstIndex) {
        firstIndex = i;
        firstFound = intent;
        break;
      }
    }
  }

  // Analyse par position du premier mot-clé rencontré
  checkCategory(_balance, BankIntent.balance);
  checkCategory(_history, BankIntent.history);
  checkCategory(_transfer, BankIntent.transfer);
  checkCategory(_otp, BankIntent.otp);
  checkCategory(_profile, BankIntent.profile);
  checkCategory(_advisor, BankIntent.advisor);

  if (firstFound != BankIntent.none) {
    return firstFound;
  }

  // 4. Si aucun mot-clé métier n'a été trouvé, repli sur n'importe quel chiffre présent
  for (final w in list) {
    final key = _digitWords[w];
    if (key != null) return intentForKey(key);
  }

  for (final w in list) {
    final key = _aloneDigit[w];
    if (key != null) return intentForKey(key);
  }

  return BankIntent.none;
}
