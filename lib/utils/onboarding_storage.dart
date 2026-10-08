import 'package:shared_preferences/shared_preferences.dart';

/// Stocke l'état de l'enrôlement initial. Lu/écrit à la fois par le
/// service d'arrière-plan (headless) et par l'interface au premier plan,
/// afin que les deux isolats restent synchronisés.
class OnboardingStorage {
  OnboardingStorage._();

  static const _kCompleted = 'onboarding_completed';
  static const _kUserName = 'user_name';
  static const _kNeedsFingerprint = 'needs_fingerprint_step';
  static const _kNeedsPin = 'needs_pin_step';
  static const _kFingerprintCount = 'fingerprint_enrolled_count';
  static const _kPinHash = 'security_pin_hash';
  static const _kFlowInProgress = 'flow_in_progress_at_ms';
  static const _kAccountProvisioned = 'account_provisioned';
  static const _kPendingAction = 'pending_action';
  static const _kLastBackgroundSpeechAt = 'last_background_speech_at_ms';
  static const _kFieldPrefix = 'field_';

  /// Le service d'arriere-plan et l'interface tournent dans deux isolats
  /// Dart distincts, chacun avec son propre cache SharedPreferences. Sans
  /// reload(), une valeur ecrite par l'un n'est pas visible par l'autre
  /// (action en attente, champs du formulaire, drapeau de flux en cours).
  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  static Future<bool> isCompleted() async {
    final p = await _prefs();
    return p.getBool(_kCompleted) ?? false;
  }

  static Future<void> setCompleted(bool value) async {
    final p = await _prefs();
    await p.setBool(_kCompleted, value);
  }

  static Future<String?> getUserName() async {
    final p = await _prefs();
    return p.getString(_kUserName);
  }

  static Future<void> setUserName(String name) async {
    final p = await _prefs();
    await p.setString(_kUserName, name);
  }

  static Future<bool> needsFingerprintStep() async {
    final p = await _prefs();
    return p.getBool(_kNeedsFingerprint) ?? false;
  }

  static Future<void> setNeedsFingerprintStep(bool value) async {
    final p = await _prefs();
    await p.setBool(_kNeedsFingerprint, value);
  }

  static Future<int> getFingerprintCount() async {
    final p = await _prefs();
    return p.getInt(_kFingerprintCount) ?? 0;
  }

  static Future<void> setFingerprintCount(int value) async {
    final p = await _prefs();
    await p.setInt(_kFingerprintCount, value);
  }

  /// Stockage generique des champs du formulaire d'identite / de compte.
  /// Permet d'ajouter ou de modifier des champs sans changer le schema.
  static Future<String?> getField(String key) async {
    final p = await _prefs();
    return p.getString('$_kFieldPrefix$key');
  }

  static Future<void> setField(String key, String value) async {
    final p = await _prefs();
    await p.setString('$_kFieldPrefix$key', value);
  }

  static Future<bool> needsPinStep() async {
    final p = await _prefs();
    return p.getBool(_kNeedsPin) ?? false;
  }

  static Future<void> setNeedsPinStep(bool value) async {
    final p = await _prefs();
    await p.setBool(_kNeedsPin, value);
  }

  static Future<bool> hasPin() async {
    final p = await _prefs();
    return p.getString(_kPinHash) != null;
  }

  static Future<void> setPinHash(String hash) async {
    final p = await _prefs();
    await p.setString(_kPinHash, hash);
  }

  static Future<String?> getPinHash() async {
    final p = await _prefs();
    return p.getString(_kPinHash);
  }

  /// Indique qu'un flux vocal (formulaire ou securite) est en cours au
  /// premier plan. Le service d'arriere-plan consulte ce flag avant de
  /// parler pour eviter deux voix simultanees si l'utilisateur redit le
  /// mot-cle pendant que l'application est deja en train de le traiter.
  ///
  /// Stocke un horodatage plutot qu'un simple booleen : si l'application
  /// est tuee en plein flux (crash, balayage), le drapeau ne peut pas
  /// rester bloque a "vrai" pour toujours et empecher definitivement le
  /// service d'arriere-plan de repondre. Il expire apres [staleAfter].
  static Future<bool> isFlowInProgress({
    Duration staleAfter = const Duration(minutes: 10),
  }) async {
    final p = await _prefs();
    final ts = p.getInt(_kFlowInProgress);
    if (ts == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    return age <= staleAfter.inMilliseconds;
  }

  static Future<void> setFlowInProgress(bool value) async {
    final p = await _prefs();
    if (value) {
      await p.setInt(_kFlowInProgress, DateTime.now().millisecondsSinceEpoch);
    } else {
      await p.remove(_kFlowInProgress);
    }
  }

  static Future<bool> isAccountProvisioned() async {
    final p = await _prefs();
    return p.getBool(_kAccountProvisioned) ?? false;
  }

  static Future<void> setAccountProvisioned(bool value) async {
    final p = await _prefs();
    await p.setBool(_kAccountProvisioned, value);
  }

  /// Action demandee par l'utilisateur apres le mot-cle (ex: "virement"),
  /// a traiter par l'interface des qu'elle est au premier plan.
  static Future<String?> getPendingAction() async {
    final p = await _prefs();
    return p.getString(_kPendingAction);
  }

  static Future<void> setPendingAction(String? value) async {
    final p = await _prefs();
    if (value == null) {
      await p.remove(_kPendingAction);
    } else {
      await p.setString(_kPendingAction, value);
    }
  }

  /// Marque l'instant où le service d'arrière-plan vient de parler, pour
  /// que l'UI (si elle s'ouvre juste après) ne répète pas le même message.
  static Future<void> markBackgroundSpeech() async {
    final p = await _prefs();
    await p.setInt(_kLastBackgroundSpeechAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> wasBackgroundSpeechRecent({
    Duration within = const Duration(seconds: 6),
  }) async {
    final p = await _prefs();
    final ts = p.getInt(_kLastBackgroundSpeechAt);
    if (ts == null) return false;
    final diff = DateTime.now().millisecondsSinceEpoch - ts;
    return diff <= within.inMilliseconds;
  }

  static Future<void> resetAll() async {
    final p = await _prefs();
    final keys = p.getKeys().where((k) =>
        k == _kCompleted ||
        k == _kUserName ||
        k == _kNeedsFingerprint ||
        k == _kNeedsPin ||
        k == _kFingerprintCount ||
        k == _kPinHash ||
        k == _kFlowInProgress ||
        k == _kAccountProvisioned ||
        k == _kPendingAction ||
        k == _kLastBackgroundSpeechAt ||
        k.startsWith(_kFieldPrefix));
    for (final k in keys.toList()) {
      await p.remove(k);
    }
  }
}
