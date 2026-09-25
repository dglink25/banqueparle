import 'package:shared_preferences/shared_preferences.dart';

/// Stocke l'état de l'enrôlement initial. Lu/écrit à la fois par le
/// service d'arrière-plan (headless) et par l'interface au premier plan,
/// afin que les deux isolats restent synchronisés.
class OnboardingStorage {
  OnboardingStorage._();

  static const _kCompleted = 'onboarding_completed';
  static const _kUserName = 'user_name';
  static const _kNeedsFingerprint = 'needs_fingerprint_step';
  static const _kFingerprintCount = 'fingerprint_enrolled_count';
  static const _kLastBackgroundSpeechAt = 'last_background_speech_at_ms';

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
    await p.remove(_kCompleted);
    await p.remove(_kUserName);
    await p.remove(_kNeedsFingerprint);
    await p.remove(_kFingerprintCount);
    await p.remove(_kLastBackgroundSpeechAt);
  }
}
