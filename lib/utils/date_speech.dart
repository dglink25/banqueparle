const List<String> _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
  'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// Date et heure prêtes à être dites : « aujourd'hui à 14 heures 05 »,
/// « hier à 9 heures », « le 12 octobre à 16 heures 30 ».
String describeWhen(DateTime at) {
  final d = at.toLocal();
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  final time = d.minute == 0
      ? 'à ${d.hour} heures'
      : 'à ${d.hour} heures ${d.minute.toString().padLeft(2, '0')}';

  if (sameDay(d, now)) return 'aujourd\'hui $time';
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'hier $time';
  return 'le ${d.day} ${_months[d.month - 1]} $time';
}
