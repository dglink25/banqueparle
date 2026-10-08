import '../utils/onboarding_storage.dart';
import '../utils/text_normalize.dart';
import 'onboarding_fields.dart';
import 'pin_enrollment_flow.dart';
import 'pin_verification.dart';
import 'transfer_service.dart';
import 'voice_dialog.dart';

/// Touche 5 - Gestion du profil. Securite : optionnelle.
///
/// Lit les coordonnees et parametres de l'utilisateur, puis permet de
/// modifier le nom, le telephone, la date de naissance et le code secret.
/// Conformement a la colonne "Optionnel" du cahier des charges, la lecture
/// et la modification des coordonnees ne demandent pas d'identite
/// renforcee. Une exception, par prudence : changer le code secret exige
/// de donner l'ancien, sinon quiconque tient le telephone deverrouille
/// pourrait le remplacer et s'emparer du second facteur.
///
/// Le numero de compte n'est pas modifiable : il est lie au role de base
/// de donnees cree a l'enrolement.
class ProfileFlow {
  final SpeakFn speak;
  final ListenFn listen;

  ProfileFlow({required this.speak, required this.listen});

  static const int kMaxModifications = 5;

  OnboardingField _field(String key) => [
        ...kPersonalInfoFields,
        ...kBankAccountFields,
      ].firstWhere((f) => f.key == key);

  Future<void> run() async {
    await _readProfile();

    for (var i = 0; i < kMaxModifications; i++) {
      final choice = await askWithRetry(
        speak: speak,
        listen: listen,
        question: i == 0
            ? 'Souhaitez-vous modifier une information ? Dites 1 pour le '
                'nom, 2 pour le telephone, 3 pour la date de naissance, '
                '4 pour le code secret, ou 0 pour terminer.'
            : 'Une autre modification ? Dites 1 pour le nom, 2 pour le '
                'telephone, 3 pour la date de naissance, 4 pour le code '
                'secret, ou 0 pour terminer.',
        maxRetries: 1,
      );
      if (choice == null) return;

      final target = _parseChoice(choice);
      if (target == null) {
        await speak('Je n\'ai pas compris votre choix.');
        continue;
      }
      if (target == 'done') {
        await speak('Gestion du profil terminee.');
        return;
      }
      await _modify(target);
    }
  }

  String? _parseChoice(String raw) {
    final words = normalizedWords(raw).toSet();
    bool has(List<String> w) => w.any(words.contains);

    if (has(['nom', 'prenom'])) return 'full_name';
    if (has(['telephone', 'numero', 'portable'])) return 'phone_number';
    if (has(['date', 'naissance', 'anniversaire'])) return 'birth_date';
    if (has(['code', 'secret'])) return 'pin';
    if (has(['terminer', 'fin', 'fini', 'rien', 'non', '0', 'zero'])) {
      return 'done';
    }
    if (has(['1', 'un', 'une'])) return 'full_name';
    if (has(['2', 'deux'])) return 'phone_number';
    if (has(['3', 'trois'])) return 'birth_date';
    if (has(['4', 'quatre'])) return 'pin';
    return null;
  }

  Future<void> _readProfile() async {
    final name = await OnboardingStorage.getField('full_name') ?? 'non renseigne';
    final birth =
        await OnboardingStorage.getField('birth_date') ?? 'non renseignee';
    final phone = await OnboardingStorage.getField('phone_number');
    final account = await OnboardingStorage.getField('account_number');
    final type = await OnboardingStorage.getField('account_type') ?? '';
    final fingers = await OnboardingStorage.getFingerprintCount();
    final hasPin = await OnboardingStorage.hasPin();

    String spell(String v) => v.split('').join(' ');
    final last4 = (account != null && account.length > 4)
        ? account.substring(account.length - 4)
        : account;

    await speak('Voici votre profil. Nom : $name. Date de naissance : '
        '$birth.');
    final phoneText = phone != null ? spell(phone) : 'non renseigne';
    final accountText = last4 != null ? spell(last4) : 'inconnu';
    final typeText = type.isNotEmpty ? ', $type' : '';
    await speak(
      'Telephone : $phoneText. Compte se terminant par $accountText'
      '$typeText.',
    );
    final String fingerText;
    if (fingers == 0) {
      fingerText = 'Aucune empreinte enregistree';
    } else if (fingers == 1) {
      fingerText = '1 empreinte enregistree';
    } else {
      fingerText = '$fingers empreintes enregistrees';
    }
    final pinText = hasPin ? 'est defini' : 'n\'est pas defini';
    await speak('$fingerText. Le code secret $pinText.');
  }

  Future<void> _modify(String target) async {
    if (target == 'pin') {
      final ok = await verifyPin(speak: speak, listen: listen);
      if (!ok) {
        await speak('Ancien code non confirme. Le code secret n\'est pas '
            'modifie.');
        return;
      }
      await PinEnrollmentFlow(speak: speak, listen: listen).run(
        introduction: 'Choisissez votre nouveau code secret a quatre '
            'chiffres.',
      );
      return;
    }

    final value = await collectFieldValue(
      speak: speak,
      listen: listen,
      field: _field(target),
    );
    if (value == null) {
      await speak('Modification annulee.');
      return;
    }
    await OnboardingStorage.setField(target, value);

    if (target == 'full_name') {
      final synced = await TransferService.updateOwnerName(value);
      await speak(
        synced
            ? 'Votre nom a ete mis a jour.'
            : 'Votre nom a ete mis a jour sur ce telephone, mais n\'a pas '
                'pu etre synchronise avec la banque. Verifiez votre '
                'connexion internet.',
      );
    } else {
      await speak('Information mise a jour.');
    }
  }
}
