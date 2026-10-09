import '../utils/digit_parser.dart';
import '../utils/onboarding_storage.dart';
import 'voice_dialog.dart';

/// -----------------------------------------------------------------------
/// Definition du formulaire d'enrolement complet.
///
/// Le cahier des charges ne precise pas la liste exacte des informations
/// a collecter. Les champs ci-dessous ont ete definis par ingenierie,
/// en s'appuyant sur les pratiques standard d'ouverture de service
/// bancaire (identification du client, rattachement du compte, securite
/// forte), et en excluant deliberement les champs peu fiables a dicter
/// au clavier vocal (voir note sur l'email plus bas).
/// -----------------------------------------------------------------------

class OnboardingField {
  /// Cle de stockage (SharedPreferences).
  final String key;

  /// Question posee a l'utilisateur.
  final String question;

  /// Si vrai, la reponse est repetee a l'utilisateur pour confirmation
  /// avant d'etre enregistree. Recommande pour toute donnee sensible ou
  /// difficile a reconnaitre correctement (chiffres, dates).
  final bool confirmBack;

  /// Transformation optionnelle appliquee a la reponse brute avant
  /// stockage et avant la confirmation orale (ex: normaliser un choix
  /// en texte clair).
  final String Function(String raw)? normalize;

  const OnboardingField(
    this.key,
    this.question, {
    this.confirmBack = true,
    this.normalize,
  });
}

/// Ne conserve que les chiffres (reconnaissance parfois renvoyee avec des
/// espaces, ou en toutes lettres). Indispensable pour que le numero de
/// compte enregistre soit identique a celui dicte par un expediteur lors
/// d'un virement.
String _normalizeDigits(String raw) {
  final direct = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (direct.isNotEmpty) return direct;
  final fromWords = extractDigits(raw, maxLength: 24);
  return fromWords.isNotEmpty ? fromWords : raw;
}

String _normalizeAccountType(String raw) {
  final t = raw.toLowerCase();
  if (t.contains('1') || t.contains('courant')) return 'Compte courant';
  if (t.contains('2') || t.contains('epargne') || t.contains('épargne')) {
    return 'Compte epargne';
  }
  return raw;
}

/// Section 1 : identite de la personne.
/// Necessaire pour l'identification client, conforme aux exigences
/// habituelles de connaissance client (KYC) d'un etablissement bancaire.
const List<OnboardingField> kPersonalInfoFields = [
  OnboardingField('full_name', 'Quel est votre nom complet ?'),
  OnboardingField(
    'birth_date',
    'Quelle est votre date de naissance ? Par exemple, dites : '
    'quinze mars mille neuf cent quatre-vingt-dix.',
  ),
  OnboardingField(
    'phone_number',
    'Quel est votre numero de telephone, pour les alertes de securite ?',
    normalize: _normalizeDigits,
  ),
];

/// Section 2 : rattachement au compte bancaire existant.
/// Note d'ingenierie : l'adresse email n'est volontairement pas demandee
/// ici. La dictee vocale d'une adresse email (caracteres speciaux, point,
/// arobase) est notoirement peu fiable et risquerait d'enregistrer une
/// adresse erronee pour un canal de securite. Le numero de telephone,
/// deja collecte, sert de canal de contact principal.
const List<OnboardingField> kBankAccountFields = [
  OnboardingField(
    'account_number',
    'Quel est votre numero de compte bancaire ?',
    normalize: _normalizeDigits,
  ),
  OnboardingField(
    'account_type',
    'Quel type de compte utilisez-vous ? Dites 1 pour compte courant, '
    'ou 2 pour compte epargne.',
    confirmBack: false,
    normalize: _normalizeAccountType,
  ),
];

/// Pose la question d'un champ, normalise la reponse, et la fait confirmer
/// oralement si le champ l'exige. Renvoie la valeur confirmee, ou null si
/// l'utilisateur n'a pas repondu apres plusieurs relances. Utilisee aussi
/// bien par le formulaire d'enrolement que par la modification du profil.
Future<String?> collectFieldValue({
  required SpeakFn speak,
  required ListenFn listen,
  required OnboardingField field,
}) async {
  while (true) {
    final rawAnswer = await askWithRetry(
      speak: speak,
      listen: listen,
      question: field.question,
    );
    if (rawAnswer == null) return null;

    final value =
        field.normalize != null ? field.normalize!(rawAnswer) : rawAnswer;

    if (!field.confirmBack) return value;

    // Les longues suites de chiffres sont epelees pour que la synthese
    // vocale ne les lise pas comme un tres grand nombre.
    final spoken = RegExp(r'^\d{5,}$').hasMatch(value)
        ? value.split('').join(' ')
        : value;

    final confirmed = await askYesNo(
      speak: speak,
      listen: listen,
      question: 'Vous avez dit : $spoken. Est-ce correct ?',
    );
    if (confirmed == true) return value;
    await speak(confirmed == false
        ? 'D\'accord, reprenons cette question.'
        : 'Je n\'ai pas pu confirmer. Reprenons cette question.');
  }
}

/// Execute une liste de champs de formulaire, un par un. Les champs deja
/// renseignes (par exemple lors d'une tentative precedente interrompue)
/// sont automatiquement ignores, ce qui permet une reprise naturelle si
/// l'utilisateur redit le mot-cle plus tard.
///
/// Renvoie false si l'utilisateur n'a pas repondu apres plusieurs
/// relances (abandon), true si tous les champs ont ete renseignes.
Future<bool> runFormFields({
  required SpeakFn speak,
  required ListenFn listen,
  required List<OnboardingField> fields,
}) async {
  for (final field in fields) {
    final existing = await OnboardingStorage.getField(field.key);
    if (existing != null && existing.isNotEmpty) {
      continue;
    }
    final value =
        await collectFieldValue(speak: speak, listen: listen, field: field);
    if (value == null) return false;
    await OnboardingStorage.setField(field.key, value);
  }
  return true;
}
