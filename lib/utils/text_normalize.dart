/// Normalise une chaine : minuscules, sans accents, ponctuation retiree,
/// espaces multiples reduits. Partagee entre la detection du mot-cle et
/// l'analyse des reponses oui/non, pour un comportement coherent.
String normalizeText(String input) {
  const withAccents = 'aaaaaaceeeeiiiinooooouuuuyy';
  const rawAccents = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  var out = input.toLowerCase();
  for (var i = 0; i < rawAccents.length; i++) {
    out = out.replaceAll(rawAccents[i], withAccents[i]);
  }
  out = out.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

/// Decoupe un texte normalise en mots (utile pour une comparaison exacte
/// mot a mot plutot qu'une recherche de sous-chaine, qui produit de faux
/// positifs : par exemple "un" est une sous-chaine de "aucun").
List<String> normalizedWords(String input) {
  final norm = normalizeText(input);
  if (norm.isEmpty) return const [];
  return norm.split(' ');
}
