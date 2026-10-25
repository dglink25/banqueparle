/// Vocabulaires restreints pour la reconnaissance hors ligne (Vosk).
///
/// Principe : quand les reponses possibles sont connues (oui/non, menu),
/// on n'ecoute que ces mots. C'est ce qui rend la reconnaissance fiable
/// malgre l'accent : le moteur choisit parmi quelques mots au lieu de
/// deviner n'importe quelle phrase du francais.
///
/// Regles issues de la documentation de Vosk :
///  - "[unk]" est obligatoire : sans lui le moteur reste bloque des qu'un
///    son sort de la grammaire. Il permet de dire "ce n'etait aucun de
///    ces mots" au lieu de forcer le mot le plus proche.
///  - la grammaire sert a construire un petit modele de langage : les mots
///    peuvent s'enchainer ("banque parlante solde") meme si les phrases
///    sont listees separement.
///  - un mot absent du vocabulaire du modele est ignore sans erreur : ne
///    lister que des mots francais courants, avec leurs accents.
///  - pas de tiret dans les mots.

/// Reponses oui/non, avec l'arret d'urgence toujours possible.
const List<String> kYesNoGrammar = [
  'oui', 'non', 'un', 'deux', 'ouais', 'exact', 'correct',
  'stop', 'arrête', 'zéro',
  'banque parlante stop', 'banque parlante arrête',
  '[unk]',
];

/// Menu des commandes (touches 1 a 6 et arret).
const List<String> kMenuGrammar = [
  'solde', 'historique', 'virement', 'transfert', 'code',
  'code de sécurité', 'profil', 'conseiller',
  'un', 'deux', 'trois', 'quatre', 'cinq', 'six',
  'stop', 'arrête', 'zéro',
  'banque parlante stop',
  '[unk]',
];

/// Choix dans la gestion du profil.
const List<String> kProfileGrammar = [
  'un', 'deux', 'trois', 'quatre',
  'nom', 'téléphone', 'date de naissance', 'code secret',
  'terminer', 'rien', 'non',
  'stop', 'arrête', 'zéro',
  '[unk]',
];

/// Mot-cle d'activation, suivi ou non d'une demande ("Banque Parlante
/// solde"). Toutes les combinaisons sont listees pour que la demande dite
/// dans la meme phrase soit reconnue.
List<String> buildWakeGrammar() {
  const wakes = ['banque parlante', 'banque parle'];
  const commands = [
    'solde', 'historique', 'virement', 'code', 'profil', 'conseiller',
    'stop', 'arrête', 'zéro',
    'un', 'deux', 'trois', 'quatre', 'cinq', 'six',
  ];
  final phrases = <String>[];
  for (final w in wakes) {
    phrases.add(w);
    for (final c in commands) {
      phrases.add('$w $c');
    }
  }
  phrases.add('[unk]');
  return phrases;
}
