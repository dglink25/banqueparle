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
  static const _kLastBackgroundSpeechAt = 'last_background_speech_at_ms';
  static const _kFieldPrefix = 'field_';

  static Future<bool> isCompleted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kCompleted) ?? false;
  }

  static Future<void> setCompleted(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCompleted, value);
  }

  static Future<String?> getUserName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUserName);
  }

  static Future<void> setUserName(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUserName, name);
  }

  static Future<bool> needsFingerprintStep() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kNeedsFingerprint) ?? false;
  }

  static Future<void> setNeedsFingerprintStep(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kNeedsFingerprint, value);
  }

  static Future<int> getFingerprintCount() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kFingerprintCount) ?? 0;
  }

  static Future<void> setFingerprintCount(int value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kFingerprintCount, value);
  }

  /// Stockage generique des champs du formulaire d'identite / de compte.
  /// Permet d'ajouter ou de modifier des champs sans changer le schema.
  static Future<String?> getField(String key) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('$_kFieldPrefix$key');
  }

  static Future<void> setField(String key, String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_kFieldPrefix$key', value);
  }

  static Future<bool> needsPinStep() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kNeedsPin) ?? false;
  }

  static Future<void> setNeedsPinStep(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kNeedsPin, value);
  }

  static Future<bool> hasPin() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPinHash) != null;
  }

  static Future<void> setPinHash(String hash) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPinHash, hash);
  }

  static Future<String?> getPinHash() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPinHash);
  }

  /// Marque l'instant où le service d'arrière-plan vient de parler, pour
  /// que l'UI (si elle s'ouvre juste après) ne répète pas le même message.
  static Future<void> markBackgroundSpeech() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastBackgroundSpeechAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> wasBackgroundSpeechRecent({
    Duration within = const Duration(seconds: 6),
  }) async {
    final p = await SharedPreferences.getInstance();
    final ts = p.getInt(_kLastBackgroundSpeechAt);
    if (ts == null) return false;
    final diff = DateTime.now().millisecondsSinceEpoch - ts;
    return diff <= within.inMilliseconds;
  }

  static Future<void> resetAll() async {
    final p = await SharedPreferences.getInstance();
    final keys = p.getKeys().where((k) =>
        k == _kCompleted ||
        k == _kUserName ||
        k == _kNeedsFingerprint ||
        k == _kNeedsPin ||
        k == _kFingerprintCount ||
        k == _kPinHash ||
        k == _kLastBackgroundSpeechAt ||
        k.startsWith(_kFieldPrefix));
    for (final k in keys.toList()) {
      await p.remove(k);
    }
  }
}
