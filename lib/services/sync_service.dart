import '../utils/onboarding_storage.dart';
import 'local_cache.dart';
import 'transfer_service.dart';

/// -----------------------------------------------------------------------
/// Synchronisation entre la base en ligne et la copie locale.
///
/// Déclenchée : à l'activation du compte, après chaque virement, au
/// démarrage du service, toutes les 20 minutes, et dans les 2 minutes qui
/// suivent un échec dû à l'absence de connexion.
///
/// Pourquoi pas une interrogation toutes les minutes : la base Neon se met
/// en veille après quelques minutes d'inactivité. Une interrogation
/// continue la maintiendrait éveillée en permanence, ce qui épuiserait le
/// quota de calcul du plan gratuit et la batterie du téléphone. Les lectures
/// demandées à la voix, elles, interrogent toujours la base en direct.
/// -----------------------------------------------------------------------
class SyncService {
  SyncService._();

  static bool _running = false;
  static const _profileKeys = [
    'full_name', 'phone_number', 'birth_date', 'account_type',
  ];

  /// Envoie le profil local vers la base.
  static Future<bool> pushLocalProfile() async {
    Future<String> field(String key) async =>
        await OnboardingStorage.getField(key) ?? '';
    return TransferService.pushProfile(
      name: await field('full_name'),
      phone: await field('phone_number'),
      birthDate: await field('birth_date'),
      accountType: await field('account_type'),
    );
  }

  /// Recopie le profil de la base sur le telephone (valeurs non vides).
  static Future<void> mergeProfile(Map<String, String> remote) async {
    for (final key in _profileKeys) {
      final value = remote[key];
      if (value != null && value.isNotEmpty) {
        await OnboardingStorage.setField(key, value);
      }
    }
  }

  static Future<void> syncAll() async {
    if (_running) return;
    _running = true;
    try {
      if (!await OnboardingStorage.isAccountProvisioned()) return;
      var sawOffline = false;

      // 1. Profil modifie hors connexion : il part en premier.
      if (await LocalCache.isProfileDirty()) {
        if (await pushLocalProfile()) {
          await LocalCache.setProfileDirty(false);
        } else {
          sawOffline = true;
        }
      }

      // 2. Solde et historique.
      final balance = await TransferService.getBalance();
      if (balance.ok) {
        await LocalCache.saveBalance(balance.value!);
      } else if (balance.offline) {
        sawOffline = true;
      }

      final history = await TransferService.getHistory(limit: 10);
      if (history.ok) {
        await LocalCache.saveHistory(history.value!);
      } else if (history.offline) {
        sawOffline = true;
      }

      // 3. Profil de la base (sauf modification locale en attente).
      if (!await LocalCache.isProfileDirty()) {
        final profile = await TransferService.getProfile();
        if (profile.ok) {
          final remote = profile.value!;
          // Compte existant dont le profil n'a jamais ete envoye.
          var missingRemotely = false;
          for (final key in const ['phone_number', 'birth_date', 'account_type']) {
            final local = await OnboardingStorage.getField(key);
            if ((remote[key] ?? '').isEmpty && (local ?? '').isNotEmpty) {
              missingRemotely = true;
            }
          }
          if (missingRemotely) {
            await pushLocalProfile();
          } else {
            await mergeProfile(remote);
          }
        } else if (profile.offline) {
          sawOffline = true;
        }
      }

      await LocalCache.setNeedsSync(sawOffline);
      if (!sawOffline) await LocalCache.markSynced();
    } finally {
      _running = false;
    }
  }
}
