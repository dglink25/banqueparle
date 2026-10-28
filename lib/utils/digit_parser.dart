import 'text_normalize.dart';

/// Extrait jusqu'a [maxLength] chiffres d'une reponse vocale : soit
/// dictes en chiffres directement (ex: "1 2 3 4"), soit en toutes
/// lettres ("un", "deux", "zéro"), y compris avec accents, homophones
/// phonetiques ("hein" pour un, "de" ou "d'eux" pour deux) et ordinaux.
String extractDigits(String raw, {int maxLength = 4}) {
  const wordToDigits = {
    // 0
    'zero': '0', 'o': '0',
    // 1
    'un': '1', 'une': '1', 'hein': '1', 'in': '1', 'ain': '1', 'premier': '1', 'premiere': '1', '1er': '1', '1re': '1',
    // 2
    'deux': '2', 'de': '2', 'des': '2', 'deu': '2', 'deus': '2', 'second': '2', 'seconde': '2', 'deuxieme': '2', '2e': '2', '2eme': '2',
    // 3
    'trois': '3', 'troisieme': '3', '3e': '3', '3eme': '3',
    // 4
    'quatre': '4', 'quatrieme': '4', '4e': '4', '4eme': '4',
    // 5
    'cinq': '5', 'cinquieme': '5', '5e': '5', '5eme': '5',
    // 6
    'six': '6', 'sixieme': '6', '6e': '6', '6eme': '6',
    // 7
    'sept': '7', 'septieme': '7', '7e': '7', '7eme': '7',
    // 8
    'huit': '8', 'huitieme': '8', '8e': '8', '8eme': '8',
    // 9
    'neuf': '9', 'neuvieme': '9', '9e': '9', '9eme': '9',
    // Nombres composes frequents
    'dix': '10', 'onze': '11', 'douze': '12', 'treize': '13', 'quatorze': '14',
    'quinze': '15', 'seize': '16', 'vingt': '20', 'trente': '30',
    'quarante': '40', 'cinquante': '50', 'soixante': '60',
  };

  final buffer = StringBuffer();
  // Normalisation préalable pour conserver les lettres sans accents et supprimer la ponctuation
  final norm = normalizeText(raw.replaceAll(RegExp(r"[-'\u2019]"), ' '));
  final tokens = norm.split(' ');

  for (final token in tokens) {
    if (buffer.length >= maxLength) break;
    if (token.isEmpty) continue;

    if (RegExp(r'^\d+$').hasMatch(token)) {
      for (final ch in token.split('')) {
        if (buffer.length >= maxLength) break;
        buffer.write(ch);
      }
    } else if (wordToDigits.containsKey(token)) {
      final digits = wordToDigits[token]!;
      for (final ch in digits.split('')) {
        if (buffer.length >= maxLength) break;
        buffer.write(ch);
      }
    }
  }
  return buffer.toString();
}
