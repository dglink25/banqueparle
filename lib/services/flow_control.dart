/// Annulation cooperative d'un parcours vocal en cours.
///
/// Quand l'utilisateur appuie sur une touche du pave numerique pendant
/// qu'un parcours tourne, ce parcours doit s'arreter immediatement (voix
/// coupee, ecoute interrompue) pour laisser place a la nouvelle commande.
/// Les fonctions "parler" et "ecouter" passees aux parcours verifient le
/// jeton et levent [FlowCancelled], qui remonte jusqu'a l'appelant.
class FlowCancelled implements Exception {
  const FlowCancelled();
  @override
  String toString() => 'FlowCancelled';
}

class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const FlowCancelled();
  }
}
