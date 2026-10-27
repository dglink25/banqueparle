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

/// Poids des mots courts. "un" (1 son) et "deux" (2 sons) perdent souvent
/// contre "[unk]" (modele de bruit, qui s'accorde a n'importe quel son bref),
/// alors que "quatre" (4 sons) passe. Repeter un mot dans la liste augmente
/// sa probabilite dans le modele de langage construit a partir de la
/// grammaire : on le fait pour les chiffres courts.
///
/// Mots voisins : un accent produit souvent "une", "hein" pour "un" et
/// "de", "des" pour "deux". Les lister permet au moteur de les proposer au
/// lieu de repondre "[unk]" ; ils sont ramenes au bon sens plus loin
/// (voice_dialog.dart et command_intent.dart).

/// Reponses oui/non, avec l'arret d'urgence toujours possible.
const List<String> kYesNoGrammar = [
  'oui', 'oui', 'non', 'non',
  'un', 'un', 'un', 'une', 'hein',
  'deux', 'deux', 'deux', 'de', 'des',
  'ouais', 'exact', 'correct',
  'stop', 'arrête', 'zéro',
  'banque parlante stop', 'banque parlante arrête',
  '[unk]',
];

/// Menu des commandes (touches 1 a 6 et arret).
const List<String> kMenuGrammar = [
  'solde', 'historique', 'virement', 'transfert', 'code',
  'code de sécurité', 'profil', 'conseiller',
  'un', 'un', 'une', 'hein', 'deux', 'deux', 'de', 'des',
  'trois', 'trois', 'quatre', 'cinq', 'cinq', 'six', 'six',
  'stop', 'arrête', 'zéro',
  'banque parlante stop',
  '[unk]',
];

/// Choix dans la gestion du profil.
const List<String> kProfileGrammar = [
  'un', 'un', 'une', 'hein', 'deux', 'deux', 'de', 'des', 'trois', 'trois',
  'quatre',
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
