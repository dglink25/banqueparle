import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Service centralisé de synthèse vocale (Text-To-Speech), en français,
/// conforme au cahier des charges (fr-FR, vitesse modérée et claire).
class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5); // vitesse modérée et claire
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _isInitialized = true;
  }

  /// Parle et ATTEND la fin réelle de la lecture (avec marge matérielle
  /// pour que le haut-parleur ne soit pas capté par le microphone).
  Future<void> speak(String text) async {
    await init();
    await _tts.stop();
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    _tts.setCompletionHandler(finish);
    _tts.setCancelHandler(finish);
    _tts.setErrorHandler((_) => finish());

    await _tts.speak(text);
    await completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {},
    );
    // Délai matériel d'extinction acoustique du haut-parleur avant toute écoute
    await Future.delayed(const Duration(milliseconds: 350));
  }

  Future<void> stop() => _tts.stop();

  /// Message d'accueil parlé systématiquement à l'ouverture, 100% vocal.
  Future<void> speakWelcome({String? name}) async {
    final greeting = (name != null && name.trim().isNotEmpty)
        ? 'Bienvenue ${name.trim()}.'
        : 'Bienvenue sur Banque Parlante.';
    await speak(
      '$greeting Que souhaitez-vous faire ? '
      'Dites simplement : solde, virement, historique, code de sécurité, '
      'profil, conseiller, ou quitter.',
    );
  }
}
