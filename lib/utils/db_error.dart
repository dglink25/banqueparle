/// Traduit une exception de connexion a la base en deux textes :
///  - [spoken] : phrase claire a dire a l'utilisateur ;
///  - [detail] : texte technique court, affiche a l'ecran pour le
///    diagnostic (ne contient jamais de mot de passe : les messages
///    d'erreur de PostgreSQL ne le reproduisent pas).
///
/// Avant, toute erreur donnait le meme message "impossible de contacter la
/// banque", ce qui rendait impossible de distinguer un mauvais nom de
/// base, un script SQL non execute, un mauvais mot de passe ou une vraie
/// panne reseau.
class DbErrorInfo {
  final String spoken;
  final String detail;

  /// Vrai si la cause est l'absence de connexion internet (et non une
  /// erreur de configuration ou de base). Permet de repondre depuis les
  /// donnees synchronisees sur le telephone, avec le message adapte.
  final bool network;

  const DbErrorInfo(this.spoken, this.detail, {this.network = false});
}

DbErrorInfo describeDbError(Object error) {
  final raw = error.toString();
  final low = raw.toLowerCase();
  final detail = raw.length > 160 ? '${raw.substring(0, 160)}...' : raw;

  if (low.contains('database') && low.contains('does not exist')) {
    return DbErrorInfo(
      'La base de données est introuvable. Le nom de la base dans la '
      'configuration est incorrect.',
      detail,
    );
  }
  if (low.contains('function') && low.contains('does not exist')) {
    return DbErrorInfo(
      'Le script SQL n\'est pas installé sur la base. Il faut l\'exécuter '
      'une fois dans la console Neon.',
      detail,
    );
  }
  if (low.contains('password authentication failed') ||
      (low.contains('role') && low.contains('does not exist')) ||
      low.contains('authentication failed')) {
    return DbErrorInfo(
      'Identifiants de la base refusés. Vérifiez le rôle et le mot de '
      'passe de provisionnement, et que le script SQL a été exécuté.',
      detail,
    );
  }
  if (low.contains('permission denied')) {
    return DbErrorInfo(
      'Droits insuffisants sur la base. Rejouez le script SQL.',
      detail,
    );
  }
  if (low.contains('endpoint') &&
      (low.contains('not specified') || low.contains('sni'))) {
    return DbErrorInfo(
      'Le serveur Neon n\'a pas identifié le projet de la connexion.',
      detail,
    );
  }
  if (low.contains('failed host lookup') ||
      low.contains('nodename nor servname')) {
    return DbErrorInfo(
      'L\'adresse du serveur est introuvable. Vérifiez que le téléphone a '
      'internet et que l\'hôte de la base est correct.',
      detail,
      network: true,
    );
  }
  if (low.contains('socketexception') ||
      low.contains('timeout') ||
      low.contains('timed out') ||
      low.contains('connection refused') ||
      low.contains('connection closed') ||
      low.contains('network')) {
    return DbErrorInfo(
      'Impossible de joindre la banque. Vérifiez votre connexion '
      'internet et réessayez.',
      detail,
      network: true,
    );
  }
  return DbErrorInfo(
    'Une erreur est survenue avec la base de données.',
    detail,
  );
}
