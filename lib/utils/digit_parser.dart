/// Extrait jusqu'a [maxLength] chiffres d'une reponse vocale : soit
/// dictes en chiffres directement (le plus courant), soit en toutes
/// lettres ("zero" a "neuf").
String extractDigits(String raw, {int maxLength = 4}) {
  const wordToDigit = {
    'zero': '0', 'un': '1', 'une': '1', 'deux': '2', 'trois': '3',
    'quatre': '4', 'cinq': '5', 'six': '6', 'sept': '7', 'huit': '8',
    'neuf': '9',
  };
  final buffer = StringBuffer();
  final tokens = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .split(RegExp(r'\s+'));

  for (final token in tokens) {
    if (buffer.length >= maxLength) break;
    if (RegExp(r'^\d+$').hasMatch(token)) {
      for (final ch in token.split('')) {
        if (buffer.length >= maxLength) break;
        buffer.write(ch);
      }
    } else if (wordToDigit.containsKey(token)) {
      buffer.write(wordToDigit[token]);
    }
  }
  return buffer.toString();
}
