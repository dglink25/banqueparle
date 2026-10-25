import '../utils/text_normalize.dart';
import 'grammars.dart';

/// -----------------------------------------------------------------------
/// Dialogue vocal generique (question, ecoute, relance si silence).
/// Utilisable aussi bien depuis le service d'arrière-plan (headless) que
/// depuis l'interface au premier plan : on lui passe simplement les
/// fonctions "parler" et "écouter" à utiliser.
/// -----------------------------------------------------------------------

typedef SpeakFn = Future<void> Function(String text);

/// Doit écouter pendant ~10 secondes et renvoyer le texte reconnu,
/// ou null/vide si rien n'a été entendu (silence).
typedef ListenFn = Future<String?> Function();

/// Indique au moteur d'ecoute que la reponse attendue est COURTE (oui/non,
/// choix de menu). Lu par sttListenOnce, qui choisit alors le modele de
/// reconnaissance "confirmation", plus fiable que la dictee libre sur les
/// mots isoles. Chaque isolat Dart (service d'arriere-plan, interface) a
/// sa propre copie de cette valeur, ce qui est voulu.
class ListenHint {
  ListenHint._();
  static bool shortAnswer = false;

  /// Vocabulaire restreint de la reponse attendue (voir grammars.dart).
  /// S'il est defini, l'ecoute utilise le moteur hors ligne Vosk, bien
  /// plus fiable que la reconnaissance generaliste sur un petit nombre de
  /// mots et sur un accent. Null : ecoute libre (noms, dates, montants).
  static List<String>? grammar;
}

/// Pose une question et attend une réponse. Si rien n'est entendu, relance
/// la question (jusqu'à [maxRetries] fois) pour ne pas boucler indéfiniment
/// et épuiser la batterie si l'utilisateur est absent.
Future<String?> askWithRetry({
  required SpeakFn speak,
  required ListenFn listen,
  required String question,
  int maxRetries = 5,
  bool shortAnswer = false,
  List<String>? grammar,
  String? retryQuestion,
}) async {
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    if (attempt == 0) {
      await speak(question);
    } else {
      // [retryQuestion] permet une relance plus courte que la question
      // initiale (un long menu ne doit pas etre repete en entier).
      await speak('Je n\'ai pas bien entendu. ${retryQuestion ?? question}');
    }
    ListenHint.shortAnswer = shortAnswer;
    ListenHint.grammar = grammar;
    String? answer;
    try {
      answer = await listen();
    } finally {
      ListenHint.shortAnswer = false;
      ListenHint.grammar = null;
    }
    if (answer != null && answer.trim().isNotEmpty) {
      return answer.trim();
    }
  }
  return null; // Abandon après plusieurs silences successifs.
}

/// Consigne par defaut ajoutee aux questions oui/non.
const String kYesNoHint = 'Dites 1 pour oui, ou 2 pour non.';

/// Interprete une reponse oui/non. Renvoie true (oui), false (non), ou
/// null quand la reponse n'est pas comprise ou est ambigue.
///
/// Les chiffres isoles ("un", "deux") sont les mots les plus mal reconnus
/// par le moteur vocal Android : sur un mot unique, il renvoie souvent
/// une approximation ("hein", "in" pour un ; "de", "deu" pour deux). Ces
/// formes sont donc acceptees, mais UNIQUEMENT quand elles constituent la
/// reponse entiere : dans une phrase, "de" ou "en" ne signifient rien.
///
/// Comparaison mot par mot (et non par sous-chaine) : "aucun" contient
/// "un" et serait sinon compris comme "oui".
///
/// [strictYes] : pour les confirmations sensibles (virement). Seuls les
/// "oui" explicites, "1" et "un" valent accord ; les approximations
/// phonetiques d'un chiffre isole ne sont plus acceptees.
///
/// Si la reponse contient a la fois un mot "oui" et un mot "non", elle
/// est consideree ambigue (null) : mieux vaut redemander que de deviner,
/// surtout avant un virement.
bool? parseYesNo(String raw, {bool strictYes = false}) {
  final words = normalizedWords(raw);
  if (words.isEmpty) return null;

  const yesWords = {
    'oui', 'ouais', 'ouai', 'wi', 'ok', 'okay', 'daccord', 'dac',
    'affirmatif', 'exact', 'exactement', 'correct', 'yes',
    '1', 'un', 'une', 'premier', 'premiere', '1er', '1re',
  };
  const noWords = {
    'non', 'nan', 'nope', 'no', 'negatif', 'annuler',
    '2', 'deux', 'deuxieme', 'second', 'seconde', '2e', '2eme',
  };
  // Approximations frequentes d'un chiffre dit seul.
  const yesAloneWords = {'hein', 'in', 'ain', 'en', 'han', 'um'};
  const noAloneWords = {'de', 'deu', 'deus', 'dos', 'dd'};

  var yes = false;
  var no = false;
  for (final w in words) {
    if (yesWords.contains(w)) yes = true;
    if (noWords.contains(w)) no = true;
  }
  if (words.length == 1) {
    // Une approximation de "un" ne vaut "oui" que hors mode strict : mal
    // reconnu, un "non" pourrait ressembler a une de ces formes, et pour
    // une operation qui deplace de l'argent, l'erreur doit toujours aller
    // dans le sens de l'annulation. Les approximations de "deux" (=non)
    // restent acceptees dans tous les cas.
    if (!strictYes && yesAloneWords.contains(words.first)) yes = true;
    if (noAloneWords.contains(words.first)) no = true;
  }

  if (yes && no) return null; // ambigu
  if (yes) return true;
  if (no) return false;
  return null;
}

/// Pose une question oui/non et ne renvoie JAMAIS "non" par defaut.
///
/// Avant ce correctif, une reponse non comprise etait traitee comme un
/// refus : un "1" mal reconnu annulait un virement ou relancait toute la
/// question. Ici, une reponse non comprise declenche une nouvelle
/// question, avec une consigne plus simple ("oui" ou "non", les mots
/// longs etant bien mieux reconnus que les chiffres isoles).
///
/// Renvoie true / false, ou null si, apres [maxAttempts] essais, aucune
/// reponse exploitable n'a ete obtenue (l'appelant choisit alors son repli,
/// en general l'annulation, qui est le choix sur).
///
/// [question] ne doit pas contenir la consigne "dites 1 pour oui..." :
/// elle est ajoutee ici. Pour une question dont les choix ne sont pas
/// oui/non (ex : repeter / terminer), fournir [hint] et [simpleHint].
Future<bool?> askYesNo({
  required SpeakFn speak,
  required ListenFn listen,
  required String question,
  String hint = kYesNoHint,
  String simpleHint = 'Dites simplement oui, ou non.',
  int maxAttempts = 4,
  bool strictYes = false,
}) async {
  var heardSomethingUnclear = false;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final String prompt;
    if (attempt == 0) {
      prompt = '$question $hint';
    } else if (heardSomethingUnclear) {
      prompt = 'Je n\'ai pas compris votre réponse. $simpleHint';
    } else {
      prompt = 'Je n\'ai pas entendu. $question $simpleHint';
    }
    await speak(prompt);

    ListenHint.shortAnswer = true; // reponse breve attendue
    ListenHint.grammar = kYesNoGrammar;
    String? answer;
    try {
      answer = await listen();
    } finally {
      ListenHint.shortAnswer = false;
      ListenHint.grammar = null;
    }
    if (answer == null || answer.trim().isEmpty) {
      heardSomethingUnclear = false;
      continue;
    }
    final parsed = parseYesNo(answer, strictYes: strictYes);
    if (parsed != null) return parsed;
    heardSomethingUnclear = true;
  }
  return null;
}
