/// Analyse d'un montant dicte a la voix.
///
/// La reconnaissance vocale renvoie des formes variees : "1250", "1 250",
/// "1\u00A0250", "12,50", "12.50", "12 euros 50", "douze virgule cinquante"
/// (ce dernier cas n'est pas gere : renvoie null et le parcours redemande).
///
/// Ne jamais supprimer simplement tous les caracteres non numeriques :
/// "12,50" deviendrait 1250, soit un montant cent fois trop eleve.
double? parseAmount(String raw) {
  var t = raw.toLowerCase();
  t = t.replaceAll('\u00A0', ' ').replaceAll('\u202F', ' ');
  t = t.replaceAll(RegExp(r'(euros?|francs?|fcfa|cfa|xof|€|\$)'), ' ');

  // "12 virgule 50" ou "12 point 50" -> "12,50"
  t = t.replaceAllMapped(
    RegExp(r'(\d+)\s*(?:virgule|point)\s*(\d{1,2})\b'),
    (m) => '${m[1]},${m[2]}',
  );

  // Separateur de milliers par espace : "1 250" -> "1250" (groupes de 3).
  var previous = '';
  while (previous != t) {
    previous = t;
    t = t.replaceAllMapped(
      RegExp(r'(\d{1,3})\s(\d{3})(?!\d)'),
      (m) => '${m[1]}${m[2]}',
    );
  }

  // "12 50" apres suppression de la devise (ex: "12 euros 50") -> 12.50
  t = t.replaceAllMapped(
    RegExp(r'^\s*(\d+)\s+(\d{2})\s*$'),
    (m) => '${m[1]},${m[2]}',
  );

  final match = RegExp(r'\d+(?:[.,]\d{1,2})?').firstMatch(t);
  if (match == null) return null;

  final value = double.tryParse(match.group(0)!.replaceAll(',', '.'));
  if (value == null || value <= 0 || value > 1000000000) return null;
  return value;
}

/// Montant pret a etre lu par la synthese vocale, avec precision :
/// 1250 -> "1250" ; 1250.5 -> "1250 virgule 50".
String speakAmount(double value) {
  if (value == 0) return 'zéro';
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  if (parts[1] == '00') return parts[0];
  return '${parts[0]} virgule ${parts[1]}';
}
