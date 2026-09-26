import '../utils/text_normalize.dart';

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

/// Pose une question et attend une réponse. Si rien n'est entendu, relance
/// la question (jusqu'à [maxRetries] fois) pour ne pas boucler indéfiniment
/// et épuiser la batterie si l'utilisateur est absent.
Future<String?> askWithRetry({
  required SpeakFn speak,
  required ListenFn listen,
  required String question,
  int maxRetries = 5,
}) async {
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    if (attempt == 0) {
      await speak(question);
    } else {
      await speak('Je n\'ai pas bien entendu. $question');
    }
    final answer = await listen();
    if (answer != null && answer.trim().isNotEmpty) {
      return answer.trim();
    }
  }
  return null; // Abandon après plusieurs silences successifs.
}

/// Interprète une réponse oui/non tolérante : accepte "1"/"oui" et
/// "2"/"non" ainsi que quelques variantes courantes.
///
/// Comparaison mot par mot (et non "contains" sur la chaîne entière) pour
/// éviter les faux positifs : par exemple "aucun" contient la sous-chaîne
/// "un" et serait à tort interprété comme "oui" avec une simple recherche
/// de sous-chaîne.
bool? parseYesNo(String raw) {
  final words = normalizedWords(raw);
  const yesWords = {'oui', '1', 'un', 'une', 'ouais', 'ok'};
  const noWords = {'non', '2', 'deux', 'no', 'nan', 'negatif'};
  for (final w in words) {
    if (yesWords.contains(w)) return true;
    if (noWords.contains(w)) return false;
  }
  return null;
}
