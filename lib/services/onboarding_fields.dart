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
  ),
  OnboardingField(
    'account_type',
    'Quel type de compte utilisez-vous ? Dites 1 pour compte courant, '
    'ou 2 pour compte epargne.',
    confirmBack: false,
    normalize: _normalizeAccountType,
  ),
];

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

    String? finalValue;
    while (finalValue == null) {
      final rawAnswer = await askWithRetry(
        speak: speak,
        listen: listen,
        question: field.question,
      );
      if (rawAnswer == null) {
        return false;
      }

      final value = field.normalize != null
          ? field.normalize!(rawAnswer)
          : rawAnswer;

      if (!field.confirmBack) {
        finalValue = value;
        break;
      }

      final confirmAnswer = await askWithRetry(
        speak: speak,
        listen: listen,
        question: 'Vous avez dit : $value. Est-ce correct ? '
            'Dites 1 pour oui, ou 2 pour non.',
        maxRetries: 2,
      );
      final yn = confirmAnswer != null ? parseYesNo(confirmAnswer) : null;
      if (yn == true) {
        finalValue = value;
      } else {
        await speak('D\'accord, reprenons cette question.');
      }
    }

    await OnboardingStorage.setField(field.key, finalValue);
  }
  return true;
}
