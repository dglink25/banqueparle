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
  int grammarAttempts = 1000,
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
    ListenHint.grammar = attempt < grammarAttempts ? grammar : null;
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

/// Interprete une reponse oui/non (vocalement : "oui", "non", "1", "2", ordinaux, etc.).
/// Renvoie true (oui), false (non), ou null quand la reponse n'est pas comprise ou est ambigue.
bool? parseYesNo(String raw, {bool strictYes = false}) {
  final cleanRaw = raw.replaceAll('[unk]', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleanRaw.isEmpty) return null;

  final clean = cleanRaw.replaceAll(RegExp(r"[-'\u2019]"), ' ');
  final words = normalizedWords(clean);
  if (words.isEmpty) return null;

  const yesWords = {
    'oui', 'ouais', 'ouai', 'wi', 'ok', 'okay', 'daccord', 'dac',
    'affirmatif', 'exact', 'exactement', 'correct', 'yes', 'valider', 'confirmer',
    'confirme', 'valide', 'absolument', 'bien', 'sur',
    '1', 'un', 'une', 'premier', 'premiere', '1er', '1re',
    'hein', 'in', 'ain', 'en',
  };

  const noWords = {
    'non', 'nan', 'nope', 'no', 'negatif', 'annuler', 'annule', 'refuser', 'refuse',
    'jamais', 'merci', 'faux', 'stop', 'quitter', 'retour', 'rien',
    '2', 'deux', 'deuxieme', 'second', 'seconde', '2e', '2eme',
    'de', 'des', 'deu', 'deus', 'dos',
  };

  var yes = false;
  var no = false;

  for (final w in words) {
    if (yesWords.contains(w)) yes = true;
    if (noWords.contains(w)) no = true;
  }

  // Vérification directe des chiffres dans le texte brut
  final digits = cleanRaw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == '1') yes = true;
  if (digits == '2') no = true;

  if (yes && no) return null; // ambigu
  if (yes) return true;
  if (no) return false;
  return null;
}

/// Pose une question oui/non et ne renvoie JAMAIS "non" par defaut.
Future<bool?> askYesNo({
  required SpeakFn speak,
  required ListenFn listen,
  required String question,
  String hint = kYesNoHint,
  String simpleHint = 'Dites simplement 1 pour oui, ou 2 pour non.',
  int maxAttempts = 4,
  bool strictYes = false,
  int googleFromAttempt = 999,
}) async {
  var heardSomethingUnclear = false;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final String prompt;
    if (attempt == 0) {
      prompt = '$question $hint';
    } else if (heardSomethingUnclear) {
      prompt = 'Je n\'ai pas bien compris votre choix. $simpleHint';
    } else {
      prompt = 'Je n\'ai pas entendu. $question $simpleHint';
    }
    await speak(prompt);

    ListenHint.shortAnswer = true;
    ListenHint.grammar = attempt >= googleFromAttempt ? null : kYesNoGrammar;
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
