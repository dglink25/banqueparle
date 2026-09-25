import 'package:flutter_tts/flutter_tts.dart';

/// Service centralisé de synthèse vocale (Text-To-Speech), en français,
/// conforme au cahier des charges (fr-FR, vitesse ~0.98x).
class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5); // vitesse modérée et claire (échelle 0-1)
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _isInitialized = true;
  }

  Future<void> speak(String text) async {
    await init();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  /// Message de bienvenue joué systématiquement à l'ouverture (manuelle
  /// ou déclenchée par le mot-clé vocal).
  Future<void> speakWelcome() async {
    await speak(
      'Bienvenue sur Banque Parlante. '
      'Je vous écoute. Dites par exemple : consulter le solde, '
      'historique des opérations, ou effectuer un virement.',
    );
  }
}
