import '../utils/onboarding_storage.dart';
import '../utils/text_normalize.dart';
import 'grammars.dart';
import 'local_cache.dart';
import 'onboarding_fields.dart';
import 'pin_enrollment_flow.dart';
import 'pin_verification.dart';
import 'sync_service.dart';
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
                'nom, 2 pour le téléphone, 3 pour la date de naissance, '
                '4 pour le code secret, ou dites terminer.'
            : 'Une autre modification ? Dites 1 pour le nom, 2 pour le '
                'téléphone, 3 pour la date de naissance, 4 pour le code '
                'secret, ou dites terminer.',
        maxRetries: 1,
        shortAnswer: true,
        grammar: kProfileGrammar,
        grammarAttempts: 1,
      );
      if (choice == null) return;

      final target = _parseChoice(choice);
      if (target == null) {
        await speak('Je n\'ai pas compris votre choix.');
        continue;
      }
      if (target == 'done') {
        await speak('Gestion du profil terminée.');
        return;
      }
      await _modify(target);
    }
  }

  String? _parseChoice(String raw) {
    if (raw.contains('[unk]')) return null;

    final clean = raw.replaceAll(RegExp(r"[-'\u2019]"), ' ');
    final words = normalizedWords(clean).toSet();
    bool has(List<String> w) => w.any(words.contains);

    if (has(['1', 'un', 'une', 'premier', 'premiere', '1er', 'hein', 'in', 'nom', 'prenom'])) {
      return 'full_name';
    }
    if (has(['2', 'deux', 'second', 'seconde', 'deuxieme', '2e', 'de', 'des', 'telephone', 'numero', 'portable', 'tel'])) {
      return 'phone_number';
    }
    if (has(['3', 'trois', 'troisieme', '3e', 'date', 'naissance', 'anniversaire'])) {
      return 'birth_date';
    }
    if (has(['4', 'quatre', 'quatrieme', '4e', 'code', 'secret', 'pin'])) {
      return 'pin';
    }
    if (has(['terminer', 'fin', 'fini', 'rien', 'non', 'quitter', 'stop', 'annuler'])) {
      return 'done';
    }

    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == '1') return 'full_name';
    if (digits == '2') return 'phone_number';
    if (digits == '3') return 'birth_date';
    if (digits == '4') return 'pin';
    if (digits == '0') return 'done';

    return null;
  }

  Future<void> _readProfile() async {
    // Profil EN LIGNE d'abord. Hors connexion, on le dit clairement et on lit la copie
    // du telephone. Une modification locale non envoyee n'est jamais ecrasee.
    if (!await LocalCache.isProfileDirty()) {
      final remote = await TransferService.getProfile();
      if (remote.ok) {
        await SyncService.mergeProfile(remote.value!);
        await LocalCache.markSynced();
        await speak('Consultation de votre profil en ligne.');
      } else {
        await LocalCache.setNeedsSync(true);
        final intro = remote.offline
            ? 'La connexion internet n\'est pas accessible. Voici votre profil enregistré en local sur ce téléphone.'
            : (remote.message ?? 'Lecture locale de votre profil.');
        await speak(intro);
      }
    } else {
      await speak(
        'Voici le profil enregistré sur ce téléphone, avec une modification '
        'locale en attente de synchronisation.',
      );
    }

    final name = await OnboardingStorage.getField('full_name') ?? 'non renseigné';
    final birth =
        await OnboardingStorage.getField('birth_date') ?? 'non renseignée';
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
    final phoneText = phone != null ? spell(phone) : 'non renseigné';
    final accountText = last4 != null ? spell(last4) : 'inconnu';
    final typeText = type.isNotEmpty ? ', $type' : '';
    await speak(
      'Téléphone : $phoneText. Compte se terminant par $accountText'
      '$typeText.',
    );
    final String fingerText;
    if (fingers == 0) {
      fingerText = 'Aucune empreinte enregistrée';
    } else if (fingers == 1) {
      fingerText = '1 empreinte enregistrée';
    } else {
      fingerText = '$fingers empreintes enregistrées';
    }
    final pinText = hasPin ? 'est défini' : 'n\'est pas défini';
    await speak('$fingerText. Le code secret $pinText.');
  }

  Future<void> _modify(String target) async {
    if (target == 'pin') {
      final ok = await verifyPin(speak: speak, listen: listen);
      if (!ok) {
        await speak('Ancien code non confirmé. Le code secret n\'est pas '
            'modifié.');
        return;
      }
      await PinEnrollmentFlow(speak: speak, listen: listen).run(
        introduction: 'Choisissez votre nouveau code secret à quatre '
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
      await speak('Modification annulée.');
      return;
    }
    await OnboardingStorage.setField(target, value);

    // Envoi vers la base. Sans connexion, la modification reste sur le
    // telephone et partira des que la connexion reviendra.
    final sent = await SyncService.pushLocalProfile();
    if (sent) {
      await LocalCache.setProfileDirty(false);
      await speak('Information mise à jour et synchronisée.');
    } else {
      await LocalCache.setProfileDirty(true);
      await LocalCache.setNeedsSync(true);
      await speak(
        'Information enregistrée sur le téléphone. Elle sera synchronisée '
        'dès que la connexion reviendra.',
      );
    }
  }
}
