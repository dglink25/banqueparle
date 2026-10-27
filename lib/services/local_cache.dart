import 'dart:convert';

import '../utils/onboarding_storage.dart';
import 'transfer_service.dart';

/// Valeur conservée sur le téléphone, avec l'instant de sa dernière
/// synchronisation.
class Cached<T> {
  final T value;
  final DateTime at;
  const Cached(this.value, this.at);
}

/// -----------------------------------------------------------------------
/// Copie locale des données bancaires (solde, historique) et indicateurs de
/// synchronisation.
///
/// Principe : la base en ligne reste la référence. Chaque lecture réussie
/// met la copie à jour ; quand la connexion est absente, l'application le
/// dit clairement puis répond avec la dernière copie synchronisée en
/// précisant sa date. Seul le virement exige internet.
/// -----------------------------------------------------------------------
class LocalCache {
  LocalCache._();

  static const _kBalance = 'cache_balance';
  static const _kHistory = 'cache_history';
  static const _kNeedsSync = 'cache_needs_sync';
  static const _kProfileDirty = 'cache_profile_dirty';
  static const _kLastSync = 'cache_last_sync_ms';

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static Future<void> saveBalance(double value) =>
      OnboardingStorage.setString(
        _kBalance,
        jsonEncode({'v': value, 't': _now}),
      );

  static Future<Cached<double>?> loadBalance() async {
    final raw = await OnboardingStorage.getString(_kBalance);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return Cached((m['v'] as num).toDouble(),
          DateTime.fromMillisecondsSinceEpoch(m['t'] as int));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveHistory(List<HistoryEntry> entries) =>
      OnboardingStorage.setString(
        _kHistory,
        jsonEncode({
          't': _now,
          'items': entries.map((e) => e.toJson()).toList(),
        }),
      );

  static Future<Cached<List<HistoryEntry>>?> loadHistory() async {
    final raw = await OnboardingStorage.getString(_kHistory);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final items = (m['items'] as List)
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return Cached(items, DateTime.fromMillisecondsSinceEpoch(m['t'] as int));
    } catch (_) {
      return null;
    }
  }

  /// Une lecture a echoue faute de connexion : la synchronisation sera
  /// retentee rapidement (voir wake_word_service).
  static Future<void> setNeedsSync(bool value) => value
      ? OnboardingStorage.setString(_kNeedsSync, '1')
      : OnboardingStorage.remove(_kNeedsSync);

  static Future<bool> needsSync() async =>
      await OnboardingStorage.getString(_kNeedsSync) != null;

  /// Le profil a ete modifie sur le telephone sans pouvoir etre envoye.
  static Future<void> setProfileDirty(bool value) => value
      ? OnboardingStorage.setString(_kProfileDirty, '1')
      : OnboardingStorage.remove(_kProfileDirty);

  static Future<bool> isProfileDirty() async =>
      await OnboardingStorage.getString(_kProfileDirty) != null;

  static Future<void> markSynced() =>
      OnboardingStorage.setString(_kLastSync, '$_now');

  static Future<DateTime?> lastSync() async {
    final raw = await OnboardingStorage.getString(_kLastSync);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
