// Vocabulaires restreints pour la reconnaissance hors ligne (Vosk).
//
// Principe : quand les reponses possibles sont connues (oui/non, menu),
// on n'ecoute que ces mots. C'est ce qui rend la reconnaissance fiable
// malgre l'accent : le moteur choisit parmi quelques mots au lieu de
// deviner n'importe quelle phrase du francais.

/// Reponses oui/non, avec l'arret d'urgence toujours possible.
const List<String> kYesNoGrammar = [
  'oui', 'oui', 'non', 'non',
  '1', 'un', 'un', 'un', 'une', 'hein', 'premier', 'première',
  '2', 'deux', 'deux', 'deux', 'de', 'des', 'second', 'seconde', 'deuxième',
  'ouais', 'exact', 'correct', 'd\'accord', 'daccord',
  'annuler', 'stop', 'arrête', 'zéro', '0',
  'banque parlante stop', 'banque parlante arrête',
  '[unk]',
];

/// Menu des commandes (touches 1 a 6 et arret).
const List<String> kMenuGrammar = [
  'solde', 'solde', 'soldes', 'mon solde', 'argent', 'combien',
  'historique', 'historiques', 'opérations', 'mouvements', 'relevé',
  'virement', 'virements', 'transfert', 'transferts',
  'code', 'code de sécurité', 'code de securite', 'otp',
  'profil', 'mon profil', 'paramètres', 'coordonnées',
  'conseiller', 'conseillère', 'assistance', 'aide',
  '1', 'un', 'un', 'une', 'hein', 'premier',
  '2', 'deux', 'deux', 'de', 'des', 'second', 'deuxième',
  '3', 'trois', 'trois', 'troisième',
  '4', 'quatre', 'quatrième',
  '5', 'cinq', 'cinq', 'cinquième',
  '6', 'six', 'six', 'sixième',
  '0', 'stop', 'arrête', 'quitter', 'fermer', 'zéro',
  'banque parlante', 'banque parle',
  'banque parlante stop',
  '[unk]',
];

/// Choix dans la gestion du profil.
const List<String> kProfileGrammar = [
  '1', 'un', 'un', 'une', 'hein', 'premier',
  '2', 'deux', 'deux', 'de', 'des', 'second', 'deuxième',
  '3', 'trois', 'trois', 'troisième',
  '4', 'quatre', 'quatrième',
  'nom', 'prénom', 'téléphone', 'date de naissance', 'code secret', 'code',
  'terminer', 'rien', 'non',
  '0', 'stop', 'arrête', 'zéro', 'quitter',
  '[unk]',
];

/// Mot-cle d'activation, suivi ou non d'une demande ("Banque Parlante
/// solde") ou commande directe.
List<String> buildWakeGrammar() {
  const wakes = ['banque parlante', 'banque parle', 'ma banque parlante'];
  const commands = [
    'solde', 'soldes', 'historique', 'virement', 'transfert',
    'code', 'profil', 'conseiller',
    'stop', 'arrête', 'quitter', 'zéro', '0',
    '1', '2', '3', '4', '5', '6',
    'un', 'deux', 'trois', 'quatre', 'cinq', 'six',
  ];
  final phrases = <String>[];
  // Mot-clé seul
  for (final w in wakes) {
    phrases.add(w);
  }
  // Mot-clé + commande
  for (final w in wakes) {
    for (final c in commands) {
      phrases.add('$w $c');
    }
  }
  // Commandes directes
  for (final c in commands) {
    phrases.add(c);
  }
  phrases.add('[unk]');
  return phrases;
}
